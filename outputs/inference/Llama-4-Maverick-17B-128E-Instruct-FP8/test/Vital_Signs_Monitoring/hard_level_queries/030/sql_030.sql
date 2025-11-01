WITH 
-- Step 1: Cohort Identification
cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id, 
    p.anchor_age,
    ie.intime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON ie.subject_id = p.subject_id
  WHERE 
    p.anchor_age BETWEEN 43 AND 53
  AND 
    ie.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE d.long_title LIKE '%Acute respiratory failure%'
    )
),

-- Step 2: VII Calculation
vii AS (
  SELECT 
    c.stay_id,
    AVG(CASE 
        WHEN di.label IN ('Heart Rate', 'Systolic Blood Pressure', 'Diastolic Blood Pressure', 'Respiratory Rate', 'Oxygen Saturation') 
        THEN ABS(ce.valuenum - (SELECT AVG(valuenum) FROM `physionet-data.mimiciv_3_1_icu.chartevents` WHERE itemid = ce.itemid)) / 
             (SELECT STDDEV(valuenum) FROM `physionet-data.mimiciv_3_1_icu.chartevents` WHERE itemid = ce.itemid)
        ELSE NULL END) AS vii
  FROM 
    cohort c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON c.stay_id = ce.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE 
    ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY 
    c.stay_id
),

-- Step 3 & 4: 95th Percentile VII and Top Quartile
vii_percentile AS (
  SELECT 
    PERCENTILE_CONT(vii.vii, 0.95) AS vii_95th
  FROM 
    vii
),
top_quartile AS (
  SELECT 
    stay_id
  FROM 
    vii
  WHERE 
    vii.vii >= (SELECT vii_95th FROM vii_percentile)
),

-- Step 5: Comparative Analysis
hypotension_tachycardia AS (
  SELECT 
    c.stay_id,
    SUM(CASE WHEN di.label = 'Mean Blood Pressure' AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS hypotension_episodes,
    SUM(CASE WHEN di.label = 'Heart Rate' AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_episodes
  FROM 
    cohort c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON c.stay_id = ce.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE 
    ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY 
    c.stay_id
)

SELECT 
  'Top Quartile' AS cohort,
  AVG(ht.hypotension_episodes) AS avg_hypotension_episodes,
  AVG(ht.tachycardia_episodes) AS avg_tachycardia_episodes,
  AVG(ie.los) AS avg_icu_los,
  SUM(CASE WHEN ha.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality
FROM 
  top_quartile tq
INNER JOIN 
  cohort c ON tq.stay_id = c.stay_id
INNER JOIN 
  hypotension_tachycardia ht ON c.stay_id = ht.stay_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_icu.icustays` ie ON c.stay_id = ie.stay_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` ha ON c.hadm_id = ha.hadm_id

UNION ALL

SELECT 
  'General ICU Population' AS cohort,
  AVG(ht.hypotension_episodes) AS avg_hypotension_episodes,
  AVG(ht.tachycardia_episodes) AS avg_tachycardia_episodes,
  AVG(ie.los) AS avg_icu_los,
  SUM(CASE WHEN ha.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality
FROM 
  cohort c
INNER JOIN 
  hypotension_tachycardia ht ON c.stay_id = ht.stay_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_icu.icustays` ie ON c.stay_id = ie.stay_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` ha ON c.hadm_id = ha.hadm_id;