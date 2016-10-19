# system-update
Update your Linux system with every update imaginable

## Installation:
```
$ git clone https://github.com/uberhacker/system-update.git
$ cd system-update
$ chmod +x system-update
$ sudo mv system-update /usr/local/bin
```

## Usage:
```
$ system-update [-s | --simulate]
```

## Examples:
Show package updates that would be applied without actually performing the updates:
```
$ system-update --simulate
```
Perform package updates along with various other updates:
```
$ system-update
```
