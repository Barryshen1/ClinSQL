SELECT 
    m.hadm_id,
    m.drug_name,
    m.start_time,
    COALESCE(m.end_time, c.dischtime) AS end_time,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(m.drug_name), r'metform') THEN 'Biguanides'
      WHEN REGEXP_CONTAINS(LOWER(m.drug_name), r'glipiz|glybur|gliben') THEN 'Sulfonylureas'
      WHEN REGEXP_CONTAINS(LOWER(m.drug_name), r'sitaglipt|saxaglipt|linaglipt') THEN 'DPP-4 inhibitors'
      WHEN REGEXP_CONTAINS(LOWER(m.drug_name), r'liraglut|exenatide|dulaglut') THEN 'GLP-1 receptor agonists'
      WHEN REGEXP_CONTAINS(LOWER(m.drug_name), r'empagliflozin|dapagliflozin|canagliflozin') THEN 'SGLT2 inhibitors'
      WHEN REGEXP_CONTAINS(LOWER(m.drug_name), r'pioglitaz') THEN 'Thiazolidinediones'
      WHEN REGEXP_CONTAINS(LOWER(m.drug_name), r'insulin') THEN 'Insulins'
      ELSE NULL
    END AS antidiabetic_class
  FROM medications m
  INNER JOIN cohort c ON m.hadm_id = c.hadm_id
  WHERE 
    REGEXP_CONTAINS(LOWER(m.drug_name), r'metform|glipiz|glybur|gliben|sitaglipt|saxaglipt|linaglipt|liraglut|exenatide|dulaglut|empagliflozin|dapagliflozin|canagliflozin|pioglitaz|insulin')
);