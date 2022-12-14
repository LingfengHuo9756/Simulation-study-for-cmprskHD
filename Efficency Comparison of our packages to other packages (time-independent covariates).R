library(fastcmprsk)
library(cmprskHD)
library(cmprsk)
library(crrp)
library(glmnet)
library(survival)
library(parallel)
library(rbenchmark)
library(MASS)
library(tictoc)
source("cmprskData_gen.R")
source("Pseudo_Entries_for_glmnet_timeindependent.R")

# define a function to run competing risks data in glmnet
glmnet_FG=function(Z,Y,fstatus,lambda_seq)
{
  ftime=NULL
  id = 1:nrow(Z)
  summary.col = 1:ncol(Z)
  p = ncol(Z)
  n_sum_ 	= length(unique(id))
  FG.dat=FG.Surv(Y,fstatus, Z, id)
  init.Y = Surv(FG.dat$surv[,2], FG.dat$surv[,3])
  glmnet(FG.dat$Z,init.Y,family="cox",weights=FG.dat$weight,maxit=10000,alpha=1,lambda=lambda_seq)
}




## Test the running times for each package based on the same number of iterations, lambdas and same penalty

# Fix p=30 and use different n
p=30
# the number of different sample sizes
n_num=5
# For each sample size, the number of times you generate new data
# Please make sure loop is large enough (>=100) since we will use z-score to exclude some outliers of running time. Small loop will lead to bad z-score estimate and wrongly exclude some correct running times, which may cause NA in our final result.
loop=100



# Define n_num null time matrices
Time=list()
for(j in 1:n_num)
{
  Time[[j]]=matrix(nrow=loop,ncol=4)
}

# Define n_num null mean time matrices
MTime=list()
for(j in 1:n_num)
{
  MTime[[j]]=matrix(nrow=1,ncol=4)
}

# In matrix Beta[[k]] (k represents the kth sample size), the (i,j) element is a betahat matrix generated by the jth method at the ith time when the data is generated
Beta=list()
beta=matrix(nrow=p,ncol=101)
b<-list()
for(i in 1:(loop*4))
{
  b[[i]]<-beta
}
for(j in 1:n_num)
{
  Beta[[j]]=matrix(b,nrow=loop,ncol=4)
}
# the increment of the sample size
incre=500
for(j in 1:n_num)
{
  # the sample size start from 1000 and increases by 500 at each loop
  n=1000+incre*(j-1)
  # In sample j, define the matrix for the distance between cmprskHD beta and true beta (row represents ith time and column represents jth lambda)
  dis_real<-matrix(nrow=loop,ncol=101)
  # In sample j, define the matrix for the maximal distance between the cmprskHD estimates and the other estimates (row represents ith time and column represents jth lambda)
  dis_others<-matrix(nrow=loop,ncol=101)
  for(i in 1:loop)
  {
    # Generate Data
    # Baseline probability of event from cause 1
    prob=0.3
    # set true beta values
    non_zero_coeff 		= c(0.5,0.5)
    beta1 				= c(non_zero_coeff, rep(0, (p - length(non_zero_coeff))))	
    beta2=rep(c(-.5,.5),p/2)
    
    # data generating
    rho=0.5
    dat=data.gen.FG(n,prob,beta1,beta2,rho=rho)
    Y=dat$surv
    cov=as.matrix(dat[,grepl('^Z',names(dat))])
    cause=dat$cause
    ftimes=Y[,1]
    fstatus=cause
    
    # cmprskHD
    # generate the largest lambda that makes all the betas shrink to 0 and the smallest lambda that makes dev.ratio the largest
    fit1<-phnet(cov,Y,fstatus=fstatus,family="finegray",alpha=1,nlambda=100,lambda.min.ratio=0.0001,standardize=TRUE,maxit=1000)
    
    # generate the lambda track based on the largest lambda and the smallest lambda set to be 0.00001
    lambda_seq<-seq(max(fit1$lambda),(0.1)^4,-(max(fit1$lambda)-(0.1)^4)/100)
    lambda_seq<-rev(lambda_seq)
    tic.clearlog()
    tic()
    fit1<-phnet(cov,Y,fstatus=fstatus,family="finegray",alpha=1,lambda=lambda_seq,standardize=TRUE,maxit=10000)
    toc(log = TRUE, quiet = TRUE)
    a<-tic.log(FALSE)
    
    # store the running time for loop i
    Time1 <- unlist(lapply(a, function(x) x$toc - x$tic))
    Time[[j]][i,1]=Time1
    # store the beta matrix for loop i
    Beta[[j]][[i,1]]<-as.matrix(fit1$beta)
    
    # glmnet
    # Time1<-benchmark(glmnet=glmnet_FG(cov,Y,cause),replications=1)
    tic.clearlog()
    tic()
    fit2<-glmnet_FG(cov,Y,cause,lambda=lambda_seq)
    toc(log = TRUE, quiet = TRUE)
    a<-tic.log(FALSE)
    # store the running time for loop i
    Time1 <- unlist(lapply(a, function(x) x$toc - x$tic))
    Time[[j]][i,2]=Time1
    # store the beta matrix for loop i
    Beta[[j]][[i,2]]<-as.matrix(fit2$beta)
    
    # Fastcrrp
    #Time1<-benchmark(fastCrrp=fastCrrp(Crisk(ftimes, fstatus) ~ cov, penalty = "LASSO",max.iter=1000,lambda=fit1$lambda),replications=1)
    tic.clearlog()
    tic()
    fit3<-fastCrrp(Crisk(ftimes, fstatus) ~ cov, penalty = "LASSO",max.iter=10000,lambda=lambda_seq)
    toc(log = TRUE, quiet = TRUE)
    a<-tic.log(FALSE)
    # store the running time for loop i
    Time1 <- unlist(lapply(a, function(x) x$toc - x$tic))
    Time[[j]][i,3]=Time1
    # store the beta matrix for loop i
    Beta[[j]][[i,3]]<-as.matrix(fit3$coef)
    
    # crrp
    tic.clearlog()
    tic()
    fit4<-crrp(time=ftimes,fstatus=fstatus,X=cov,penalty="LASSO",lambda=lambda_seq,max.iter=10000)
    toc(log = TRUE, quiet = TRUE)
    a<-tic.log(FALSE)
    # store the running time for loop i
    Time1 <- unlist(lapply(a, function(x) x$toc - x$tic))
    Time[[j]][i,4]=Time1
    # store the beta matrix for loop i
    Beta[[j]][[i,4]]<-as.matrix(fit4$beta)
    #Time[[j]][i,4]=as.numeric(difftime(strptime(end_time, "%Y-%m-%d %H:%M:%S"),strptime( start_time, "%Y-%m-%d %H:%M:%S"),units='secs'))
    
    
    # Calculate the distance between the estimates and the real parameters for each lambda and draw the graph 
    
    for(k in 1:length(lambda_seq))
    {
      dis_real[i,k]<-sum(abs(Beta[[j]][[i,1]][,length(lambda_seq)+1-k]-beta1))
    }
    
    # Calculate the maximal distance between the cmprskHD estimates and the other estimates for each lambda and draw the graph 
    for(k in 1:length(lambda_seq))
    {
      dis<-rep(0,3)
      for(l in 1:2)
      {
        dis[l]<-sum(abs(Beta[[j]][[i,1]][,length(lambda_seq)+1-k]-Beta[[j]][[i,l+1]][,length(lambda_seq)+1-k]))
      }
      dis[3]<-sum(abs(Beta[[j]][[i,1]][,length(lambda_seq)+1-k]-Beta[[j]][[i,4]][,k]))
      dis_others[i,k]<-max(dis)
    }
    
  }
  
  # for sample j, calculate the mean running time for each package
  for(t in 1:4)
  {
    A=Time[[j]][,t]
    MTime[[j]][t]=mean(Time[[j]][((A-mean(A))/sd(A))<=1,t])
  }
  
  # for sample j, calculate the mean distance between cmprskHD beta and true beta
  dis_real=colMeans(dis_real)
  # for sample j, calculate the mean maximal distance between cmprskHD beta and the beta estimated by other packages 
  dis_others=colMeans(dis_others)
  
  # draw the graphs of comparisons of beta
  # store the graph pictures in the same directory of this R script
  png(file = paste0("graph_", j, ".png"))
  # draw the two curves within one graph
  plot(lambda_seq, dis_real, type="o", col="blue", pch="o", lty=1, ylim=c(0,2),xlab="lambda",ylab="L1-norm")
  points(lambda_seq, dis_others, col="red", pch="*")
  lines(lambda_seq, dis_others, col="red",lty=2)
  legend(0.01,2,legend=c("comparison with true parameters","comparison with other estimates"), col=c("blue","red"),
         pch=c("o","*"),lty=c(1,2), ncol=1)
  dev.off()
}

# print out the average running time for each package under each sample size (row represents sample size and column represents package)
B=MTime[[1]]
for(i in 2:n_num)
{
  B=rbind(B,MTime[[i]])
}
B=rbind(c("cmprskHD","glmnet","fastcmprsk","crrp"),B)
print(B)
