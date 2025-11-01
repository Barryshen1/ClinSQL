WITH pneumonia_codes AS (
  SELECT icd_code, icd_version
  FROM UNNEST([
    STRUCT('481' AS icd_code, 9 AS icd_version),
    ('482%', 9), ('483%', 9), ('485', 9), ('486', 9), ('5070', 9), ('5078', 9),
    ('J12%', 10), ('J13', 10), ('J14', 10), ('J15%', 10), ('J16%', 10), ('J18%', 10), ('J690', 10), ('J698', 10)
  ])
),
pneumonia_admissions AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (
    (icd_version = 9 AND (
        icd_code IN ('481','485','486','5070','5078') OR
        icd_code LIKE '482%' OR icd_code LIKE '483%'
    )) OR
    (icd_version = 10 AND (
        icd_code IN ('J13','J14','J690','J698') OR
        icd_code LIKE 'J12%' OR icd_code LIKE 'J15%' OR 
        icd_code LIKE 'J16%' OR icd_code LIKE 'J18%'
    ))
  )
),
base AS (
  SELECT 
    p.subject_id, p.gender, a.hadm_id, a.admittime, a.dischtime, 
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN pneumonia_admissions pa
    ON a.hadm_id = pa.hadm_id
  WHERE 
    p.gender = 'M' AND 
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 39 AND 49
),
base_with_los AS (
  SELECT 
    *,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      WHEN DATE_DIFF(dischtime, admittime, DAY) >= 8 THEN '8+'
      ELSE NULL 
    END AS los_category
  FROM base
  WHERE DATE_DIFF(dischtime, admittime, DAY) >= 1  -- Exclude 0-day stays
),
base_with_icu_flag AS (
  SELECT 
    b.*,
    MAX(CASE WHEN i.intime <= DATETIME_ADD(b.admittime, INTERVAL 1 DAY) THEN 1 ELSE 0 END) AS icu_status
  FROM base_with_los b
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON b.hadm_id = i.hadm_id
    AND i.intime >= b.admittime
  GROUP BY 1,2,3,4,5,6,7,8,9  -- Fixed: Added 9th column (los_category) to GROUP BY
),
comorbidity AS (
  SELECT 
    d.subject_id, d.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE NOT EXISTS (
    SELECT 1 FROM pneumonia_codes pc
    WHERE 
      d.icd_version = pc.icd_version AND
      (d.icd_code = pc.icd_code OR 
       (CONTAINS_SUBSTR(pc.icd_code, '%') AND d.icd_code LIKE pc.icd_code))
  )
  GROUP BY d.subject_id, d.hadm_id
),
base_with_comorbid AS (
  SELECT 
    b.*,
    COALESCE(c.comorbidity_count, 0) AS comorbidity_count
  FROM base_with_icu_flag b
  LEFT JOIN comorbidity c
    ON b.hadm_id = c.hadm_id AND b.subject_id = c.subject_id
),
group_data AS (
  SELECT 
    los_category,
    icu_status,
    COUNT(hadm_id) AS n_admissions,
    SUM(hospital_expire_flag) AS n_deaths,
    (SUM(hospital_expire_flag) / COUNT(hadm_id)) * 100 AS mortality_rate,
    AVG(comorbidity_count) AS avg_comorbidity_count
  FROM base_with_comorbid
  GROUP BY los_category, icu_status
),
skeleton AS (
  SELECT los_category, icu_status
  FROM UNNEST(['1-3','4-7','8+']) AS los_category
  CROSS JOIN UNNEST([0,1]) AS icu_status
),
combined AS (
  SELECT 
    s.los_category,
    s.icu_status,
    COALESCE(g.n_admissions, 0) AS n_admissions,
    COALESCE(g.n_deaths, 0) AS n_deaths,
    g.mortality_rate,
    g.avg_comorbidity_count
  FROM skeleton s
  LEFT JOIN group_data g
    ON s.los_category = g.los_category AND s.icu_status = g.icu_status
),
diff AS (
  SELECT 
    los_category,
    MAX(IF(icu_status=1, mortality_rate, NULL)) AS mort_icu,
    MAX(IF(icu_status=0, mortality_rate, NULL)) AS mort_non_icu
  FROM combined
  GROUP BY los_category
)
SELECT 
  c.los_category,
  c.icu_status,
  c.n_admissions,
  c.n_deaths,
  c.mortality_rate,
  c.avg_comorbidity_count,
  CASE 
    WHEN c.icu_status = 1 THEN d.mort_icu - d.mort_non_icu 
    ELSE NULL 
  END AS abs_diff,
  CASE 
    WHEN c.icu_status = 1 AND d.mort_non_icu <> 0 THEN 
        (d.mort_icu - d.mort_non_icu) / d.mort_non_icu * 100 
    WHEN c.icu_status = 1 THEN NULL 
    ELSE NULL 
  END AS rel_diff_percent
FROM combined c
LEFT JOIN diff d
  ON c.los_category = d.los_category
ORDER BY 
  CASE c.los_category 
    WHEN '1-3' THEN 1 
    WHEN '4-7' THEN 2 
    ELSE 3 
  END,
  c.icu_status DESC;