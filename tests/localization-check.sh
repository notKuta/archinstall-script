#!/bin/bash

sed "s/\#en_US.UTF-8\ UTF-8/en_US.UTF-8\ UTF-8/g" locale.gen > tmp && mv tmp locale.gen
