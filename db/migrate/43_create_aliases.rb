class CreateAliases < ActiveRecord::Migration[5.1]
  def change
    create_table :level_aliases do |t|
      t.references :level
      t.string     :alias
    end

    create_table :player_aliases do |t|
      t.references :player
      t.string     :alias
    end

    [
      ['S-C-19-04',  '-++'  ],
      ['S-X-19-04',  'clr'  ],
      ['!-C-19',     'cfl'  ],
      ['S-X-13-01',  'sqn'  ],
      ['S-A-19-03',  'ils'  ],
      ['!-A-18',     'eeny' ],
      ['!-A-18',     'meeny'],
      ['S-E-18-04',  '40k'  ],
      ['SU-B-17-04', 'sss'  ]
    ].each{ |l|
      Level.find_by(name: l[0]).add_alias(l[1])
    }

    [
      [42585,  'jp'       ],
      [137646, 'oj'       ],
      [137646, 'ooj'      ],
      [121727, 'nw'       ],
      [41948,  'xaelar'   ],
      [54303,  'Eddy'     ],
      [103732, 'Maelstrom'],
      [103732, 'maestro'  ],
      [176553, 'GOK'      ],
      [176553, 'wolf'     ],
      [56393,  'maaz'     ],
      [41759,  'golf'     ],
      [43409,  'Borlin'   ],
      [68440,  'Nim'      ],
      [244029, 'paul'     ],
      [220878, 'mega'     ],
      [240323, 'miga'     ],
      [59984,  'Sim'      ],
      [287062, 'kk'       ],
      [139965, 'DS'       ],
      [116947, 'Sky'      ],
      [106570, 'Espy'     ],
      [59993,  'Muz'      ],
      [117031, 'Mel'      ],
      [51186,  'Natey'    ],
      [66067,  'pepsi'    ],
      [45679,  'Dune'     ],
      [47266,  'Analu'    ],
      [286822, 'Mrow'     ],
      [60861,  'SV'       ],
      [205571, 'aud'      ],
      [170323, 'Cheby'    ],
      [121140, 'Seitaro'  ],
      [54050,  'CCS'      ],
      [233161, 'Emm'      ],
      [162041, 'ps'       ],
      [57522,  'jroe'     ],
      [198308, 'Cube'     ],
      [41836,  'Kost'     ],
      [202008, 'Raif'     ]
    ].each{ |p|
      Player.find_by(metanet_id: p[0]).add_alias(p[1])
    }
  end
end