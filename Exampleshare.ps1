Configuration ExampleShare
{
   # A Configuration block indicates a DSC file. It can have zero or more
   # Node blocks. Normal PowerShell code can also appear here.
   Import-DscResource –ModuleName 'PSDesiredStateConfiguration'
   Import-DscResource -Module xSmbShare 

   # Nodes are the endpoint we wish to configure
   # Each host should have its own Node block
   Node "2515-Henry" 
   {
      # Node blocks specify one or more resource blocks. Resources are simply
      # PowerShell modules that implement the logic of "how" to execute a task.
      File CreateFolder
      {
         DestinationPath = 'C:\Repo'
         Type = 'Directory'
         Ensure = 'Present'
      }
      xSmbShare MySMBShare
      {
          Ensure      = "Present"
          Name        = "MyRepo"
          Path        = "C:\Repo"
          ReadAccess  = "SEEYAY\Domain Users"
          FullAccess  = "SEEYAY\Domain Admins"
          Description = "Proof of concept share"
          DependsOn = '[File]CreateFolder'
      }
   }
}

