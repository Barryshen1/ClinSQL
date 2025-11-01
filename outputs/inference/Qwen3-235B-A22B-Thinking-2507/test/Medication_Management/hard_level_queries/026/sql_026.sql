WITH base_population AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 76 AND 86
),
pneumonia_admissions AS (
  SELECT 
    bp.hadm_id,
    bp.subject_id,
    bp.admittime,
    bp.dischtime,
    bp.hospital_expire_flag
  FROM base_population bp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON bp.hadm_id = d.hadm_id
  WHERE 
    (d.icd_version = 9 AND d.icd_code IN ('480','481','482','483','484','485','486','4870'))
    OR (d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) IN ('J12','J13','J14','J15','J16','J17','J18'))
),
med_complexity AS (
  SELECT 
    pa.hadm_id,
    COUNT(DISTINCT e.medication) AS med_complexity
  FROM pneumonia_admissions pa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON pa.hadm_id = e.hadm_id
    AND e.charttime >= pa.admittime
    AND e.charttime < DATETIME_ADD(pa.admittime, INTERVAL 7 DAY)
  GROUP BY pa.hadm_id
),
readmission_flag AS (
  SELECT 
    pa.hadm_id,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = pa.subject_id
          AND a2.admittime > pa.dischtime
          AND a2.admittime <= DATETIME_ADD(pa.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM pneumonia_admissions pa
),
analysis_base AS (
  SELECT 
    pa.hadm_id,
    pa.hospital_expire_flag,
    mc.med_complexity,
    DATETIME_DIFF(pa.dischtime, pa.admittime, SECOND) / (24 * 60 * 60) AS los_days,
    rf.readmitted_30d,
    NTILE(3) OVER (ORDER BY mc.med_complexity) AS tertile
  FROM pneumonia_admissions pa
  LEFT JOIN med_complexity mc
    ON pa.hadm_id = mc.hadm_id
  LEFT JOIN readmission_flag rf
    ON pa.hadm_id = rf.hadm_id
)
SELECT 
  tertile,
  COUNT(*) AS count_admissions,
  MIN(med_complexity) AS min_med_complexity,
  AVG(med_complexity) AS avg_med_complexity,
  MAX(med_complexity) AS max_med_complexity,
  AVG(los_days) AS mean_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  AVG(readmitted_30d) * 100 AS readmission_30d_pct
FROM analysis_base
GROUP BY tertile
ORDER BY tertile;