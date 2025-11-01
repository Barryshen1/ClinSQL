WITH cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - 2008 BETWEEN 75 AND 85
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
      WHERE icd.icd_code = diag.icd_code
        AND icd.icd_version = diag.icd_version
        AND (
          (LOWER(icd.long_title) LIKE '%failure%' 
           AND (LOWER(icd.long_title) LIKE '%liver%' OR LOWER(icd.long_title) LIKE '%hepatic%'))
          OR LOWER(icd.long_title) LIKE '%necrosis%liver%'
        )
    )
),

general_cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - 2008 BETWEEN 75 AND 85
),

total_general AS (SELECT COUNT(*) AS n FROM general_cohort),

cohort_stats AS (
  SELECT
    COUNTIF(hospital_expire_flag = 1) AS deaths,
    COUNT(*) AS total_patients,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los_days
  FROM cohort
),

patient_max_bili AS (
  SELECT
    c.hadm_id,
    MAX(l.valuenum) AS max_bili
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON c.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON l.itemid = li.itemid
  WHERE l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND li.label = 'BILIRUBIN, TOTAL'
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'mg/dL'
  GROUP BY c.hadm_id
),

max_instability AS (
  SELECT MAX(sofa_liver) AS max_score
  FROM (
    SELECT
      CASE
        WHEN pmb.max_bili IS NULL THEN 0
        WHEN pmb.max_bili < 1.2 THEN 0
        WHEN pmb.max_bili < 2.0 THEN 1
        WHEN pmb.max_bili < 6.0 THEN 2
        WHEN pmb.max_bili < 12.0 THEN 3
        ELSE 4
      END AS sofa_liver
    FROM cohort c
    LEFT JOIN patient_max_bili pmb ON c.hadm_id = pmb.hadm_id
  ) sub
),

-- Critical lab frequencies: bilirubin >2.0 mg/dL
bili_abn_cohort AS (
  SELECT COUNT(DISTINCT c.hadm_id) AS num_abn
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON c.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON l.itemid = li.itemid
  WHERE l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND li.label = 'BILIRUBIN, TOTAL'
    AND l.valuenum > 2.0
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'mg/dL'
),
bili_abn_general AS (
  SELECT COUNT(DISTINCT g.hadm_id) AS num_abn
  FROM general_cohort g
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON g.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON l.itemid = li.itemid
  WHERE l.charttime BETWEEN g.admittime AND TIMESTAMP_ADD(g.admittime, INTERVAL 48 HOUR)
    AND li.label = 'BILIRUBIN, TOTAL'
    AND l.valuenum > 2.0
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'mg/dL'
),

-- INR >1.5
inr_abn_cohort AS (
  SELECT COUNT(DISTINCT c.hadm_id) AS num_abn
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON c.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON l.itemid = li.itemid
  WHERE l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND li.label = 'INR'
    AND l.valuenum > 1.5
    AND l.valuenum IS NOT NULL
),
inr_abn_general AS (
  SELECT COUNT(DISTINCT g.hadm_id) AS num_abn
  FROM general_cohort g
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON g.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON l.itemid = li.itemid
  WHERE l.charttime BETWEEN g.admittime AND TIMESTAMP_ADD(g.admittime, INTERVAL 48 HOUR)
    AND li.label = 'INR'
    AND l.valuenum > 1.5
    AND l.valuenum IS NOT NULL
),

-- Albumin <3.0 g/dL
alb_abn_cohort AS (
  SELECT COUNT(DISTINCT c.hadm_id) AS num_abn
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON c.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON l.itemid = li.itemid
  WHERE l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND li.label = 'ALBUMIN'
    AND l.valuenum < 3.0
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'g/dL'
),
alb_abn_general AS (
  SELECT COUNT(DISTINCT g.hadm_id) AS num_abn
  FROM general_cohort g
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON g.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON l.itemid = li.itemid
  WHERE l.charttime BETWEEN g.admittime AND TIMESTAMP_ADD(g.admittime, INTERVAL 48 HOUR)
    AND li.label = 'ALBUMIN'
    AND l.valuenum < 3.0
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'g/dL'
)

SELECT
  COALESCE(mi.max_score, 0) AS max_instability_score,
  IF(cs.total_patients = 0, NULL, cs.deaths * 100.0 / cs.total_patients) AS mortality_percent,
  cs.avg_los_days AS avg_los_days,
  IF(cs.total_patients = 0, NULL, bc.num_abn * 100.0 / cs.total_patients) AS bili_freq_cohort_percent,
  IF(gt.n = 0, NULL, bg.num_abn * 100.0 / gt.n) AS bili_freq_general_percent,
  IF(cs.total_patients = 0, NULL, ic.num_abn * 100.0 / cs.total_patients) AS inr_freq_cohort_percent,
  IF(gt.n = 0, NULL, ig.num_abn * 100.0 / gt.n) AS inr_freq_general_percent,
  IF(cs.total_patients = 0, NULL, ac.num_abn * 100.0 / cs.total_patients) AS albumin_freq_cohort_percent,
  IF(gt.n = 0, NULL, ag.num_abn * 100.0 / gt.n) AS albumin_freq_general_percent
FROM max_instability mi
CROSS JOIN cohort_stats cs
CROSS JOIN (SELECT num_abn FROM bili_abn_cohort) bc
CROSS JOIN (SELECT num_abn FROM bili_abn_general) bg
CROSS JOIN (SELECT num_abn FROM inr_abn_cohort) ic
CROSS JOIN (SELECT num_abn FROM inr_abn_general) ig
CROSS JOIN (SELECT num_abn FROM alb_abn_cohort) ac
CROSS JOIN (SELECT num_abn FROM alb_abn_general) ag
CROSS JOIN total_general gt;