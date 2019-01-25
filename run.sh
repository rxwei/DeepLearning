#/usr/bin/env bash

MODULE=DeepLearning
ROOT=$HOME/$MODULE
SOURCES=$ROOT/Sources/$MODULE
DEST=$ROOT/Generated.swift
SWIFT=$HOME/usr/bin/swift

echo '' > $DEST
cat $SOURCES/Helpers.swift >> $DEST
cat $SOURCES/Initializers.swift >> $DEST
cat $SOURCES/Layer.swift >> $DEST
cat $SOURCES/Loss.swift >> $DEST
cat $SOURCES/Optimizer.swift >> $DEST

cat $ROOT/Sources/MNIST/main.swift >> $DEST
sed -i 's/import DeepLearning//g' $DEST
$SWIFT Generated.swift
