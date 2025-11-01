WITH ugib_codes AS (
  SELECT DISTINCT di.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE di.icd_version = 'ICD-10'
    AND (LOWER(dd.long_title) LIKE '%gastrointestinal hemorrhage%'
         OR LOWER(dd.long_title) LIKE '%upper gastrointestinal bleed%'
         OR LOWER(dd.long_title) LIKE '%peptic ulcer%'
         OR LOWER(dd.long_title) LIKE '%esophageal varices%'
         OR LOWER(dd.long_title) LIKE '%gastritis with hemorrhage%')
),
base_cohort AS (
  SELECT DISTINCT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND a.admittime >= TIMESTAMP('2008-01-01')
    AND i.stay_id = (
      SELECT MIN(stay_id) 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i2 
      WHERE i2.subject_id = i.subject_id AND i2.hadm_id = i.hadm_id
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN ugib_codes uc ON d.icd_code = uc.icd_code
      WHERE d.subject_id = p.subject_id AND d.hadm_id = a.hadm_id
    )
),
non_ugib_base AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND a.admittime >= TIMESTAMP('2008-01-01')
    AND i.stay_id = (
      SELECT MIN(stay_id) 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i2 
      WHERE i2.subject_id = i.subject_id AND i2.hadm_id = i.hadm_id
    )
    AND NOT EXISTS (
      SELECT 1 
      FROM ugib_codes uc
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON d.icd_code = uc.icd_code AND d.subject_id = p.subject_id AND d.hadm_id = a.hadm_id
    )
    AND RAND() < 0.001  -- Random sample ~1000 controls
),
vitals AS (
  SELECT 
    bc.subject_id,
    bc.stay_id,
    bc.intime,
    c.charttime,
    c.itemid,
    c.valuenum
  FROM base_cohort bc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c 
    ON bc.subject_id = c.subject_id 
    AND bc.stay_id = c.stay_id
  WHERE c.charttime <= bc.intime + INTERVAL 48 HOUR
    AND c.valuenum IS NOT NULL 
    AND c.valuenum > 0
    AND c.itemid IN (220045, 220052, 220210)  -- HR, MAP, RR
    AND ((c.itemid = 220045 AND c.valuenum BETWEEN 40 AND 200)  -- HR bounds
      OR (c.itemid = 220052 AND c.valuenum BETWEEN 0 AND 200)    -- MAP bounds
      OR (c.itemid = 220210 AND c.valuenum BETWEEN 0 AND 60))    -- RR bounds
),
vital_summary AS (
  SELECT 
    subject_id,
    SUM(CASE 
      WHEN itemid = 220045 THEN ABS(valuenum - 80) / 20.0  -- HR instability
      WHEN itemid = 220052 THEN GREATEST(0, (65 - valuenum) / 10.0)  -- MAP hypotension penalty
      WHEN itemid = 220210 THEN GREATEST(0, (valuenum - 16) / 4.0)  -- RR tachypnea penalty
      ELSE 0
    END) AS instability_index
  FROM vitals
  GROUP BY subject_id
),
instability_index AS (
  SELECT 
    bc.*,
    COALESCE(vs.instability_index, 0) AS instability_index
  FROM base_cohort bc
  LEFT JOIN vital_summary vs ON bc.subject_id = vs.subject_id
),
non_ugib_instability AS (
  SELECT 
    nub.*,
    COALESCE(vs.instability_index, 0) AS instability_index
  FROM non_ugib_base nub
  LEFT JOIN (
    SELECT 
      subject_id,
      SUM(CASE 
        WHEN itemid = 220045 THEN ABS(valuenum - 80) / 20.0
        WHEN itemid = 220052 THEN GREATEST(0, (65 - valuenum) / 10.0)
        WHEN itemid = 220210 THEN GREATEST(0, (valuenum - 16) / 4.0)
        ELSE 0
      END) AS instability_index
    FROM (
      SELECT 
        nub.subject_id,
        nub.stay_id,
        nub.intime,
        c.charttime,
        c.itemid,
        c.valuenum
      FROM non_ugib_base nub
      INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c 
        ON nub.subject_id = c.subject_id AND nub.stay_id = c.stay_id
      WHERE c.charttime <= nub.intime + INTERVAL 48 HOUR
        AND c.valuenum IS NOT NULL AND c.valuenum > 0
        AND c.itemid IN (220045, 220052, 220210)
        AND ((c.itemid = 220045 AND c.valuenum BETWEEN 40 AND 200)
          OR (c.itemid = 220052 AND c.valuenum BETWEEN 0 AND 200)
          OR (c.itemid = 220210 AND c.valuenum BETWEEN 0 AND 60))
    ) non_ugib_vitals
    GROUP BY subject_id
  ) vs ON nub.subject_id = vs.subject_id
),
ugib_cohort AS (
  SELECT *
  FROM instability_index
  WHERE instability_index IS NOT NULL
),
percentiles AS (
  SELECT 
    APPROX_QUANTILES(instability_index, 20)[OFFSET(19)] AS p95_index,
    APPROX_QUANTILES(instability_index, 10)[OFFSET(9)] AS p90_index
  FROM ugib_cohort
),
top_decile_ugib AS (
  SELECT u.*
  FROM ugib_cohort u
  CROSS JOIN percentiles p
  WHERE u.instability_index >= p.p90_index
),
top_decile_controls AS (
  SELECT nu.*
  FROM non_ugib_instability nu
  CROSS JOIN percentiles p
  WHERE nu.instability_index < p.p90_index  -- Lower instability for controls
  ORDER BY RAND()
  LIMIT (SELECT COUNT(*) FROM top_decile_ugib)
),
vitals_flags AS (
  SELECT 
    v.subject_id,
    MAX(CASE WHEN v.itemid = 220045 AND v.valuenum > 100 THEN 1 ELSE 0 END) AS any_tachycardia,
    MAX(CASE WHEN v.itemid = 220052 AND v.valuenum < 65 THEN 1 ELSE 0 END) AS any_hypotension,
    MAX(CASE WHEN v.itemid = 220210 AND v.valuenum > 20 THEN 1 ELSE 0 END) AS any_tachypnea
  FROM (
    SELECT subject_id, itemid, valuenum FROM vitals
    UNION ALL
    SELECT subject_id, itemid, valuenum FROM (
      SELECT 
        nub.subject_id,
        nub.stay_id,
        c.itemid,
        c.valuenum
      FROM non_ugib_base nub
      INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c 
        ON nub.subject_id = c.subject_id AND nub.stay_id = c.stay_id
      WHERE c.charttime <= nub.intime + INTERVAL 48 HOUR
        AND c.valuenum IS NOT NULL AND c.valuenum > 0
        AND c.itemid IN (220045, 220052, 220210)
        AND ((c.itemid = 220045 AND c.valuenum BETWEEN 40 AND 200)
          OR (c.itemid = 220052 AND c.valuenum BETWEEN 0 AND 200)
          OR (c.itemid = 220210 AND c.valuenum BETWEEN 0 AND 60))
    )
  ) v
  GROUP BY v.subject_id
),
outcomes AS (
  SELECT 
    'top_decile_ugib' AS group_name,
    vf.any_tachycardia,
    vf.any_hypotension,
    vf.any_tachypnea,
    EXTRACT(DAY FROM td.los) AS icu_los,
    CAST(td.hospital_expire_flag AS FLOAT) AS mortality
  FROM top_decile_ugib td
  LEFT JOIN vitals_flags vf ON td.subject_id = vf.subject_id

  UNION ALL

  SELECT 
    'controls' AS group_name,
    vf.any_tachycardia,
    vf.any_hypotension,
    vf.any_tachypnea,
    EXTRACT(DAY FROM c.los) AS icu_los,
    CAST(c.hospital_expire_flag AS FLOAT) AS mortality
  FROM top_decile_controls c
  LEFT JOIN vitals_flags vf ON c.subject_id = vf.subject_id
),
comparison AS (
  SELECT 
    group_name,
    AVG(any_tachycardia) * 100 AS pct_tachycardia,
    AVG(any_hypotension) * 100 AS pct_hypotension,
    AVG(any_tachypnea) * 100 AS pct_tachypnea,
    AVG(icu_los) AS avg_icu_los,
    AVG(mortality) * 100 AS mortality_pct
  FROM outcomes
  GROUP BY group_name
)
SELECT 
  p.p95_index AS p95_instability_index,
  c.*
FROM percentiles p
CROSS JOIN comparison c
ORDER BY group_name;