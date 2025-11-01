WITH readmit_flags AS (
  -- Compute 30-day readmission flag per hadm_id
  SELECT 
    a1.*,
    CASE 
      WHEN a2.admittime IS NOT NULL 
           AND a2.admittime <= TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY) 
      THEN 1 
      ELSE 0 
    END AS readmit_30d_flag
  FROM (
    SELECT *, 
           ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  ) a1
  LEFT JOIN (
    SELECT *, 
           ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  ) a2 
    ON a1.subject_id = a2.subject_id 
    AND a1.rn + 1 = a2.rn
),
cohort_stays AS (
  -- Define qualifying ICU stays with admission outcomes
  SELECT 
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.intime,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    rf.readmit_30d_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS hospital_los_days
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.hadm_id = a.hadm_id
  INNER JOIN readmit_flags rf
    ON a.hadm_id = rf.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
        ON diag.icd_code = d_icd.icd_code 
        AND diag.icd_version = d_icd.icd_version
      WHERE diag.subject_id = icu.subject_id
        AND diag.hadm_id = icu.hadm_id
        AND LOWER(d_icd.long_title) LIKE '%hyperosmolar%'
    )
),
procedure_counts AS (
  -- Count procedures in first 48 hours per ICU stay
  SELECT 
    cs.*,
    COUNT(pe.itemid) AS num_procedures_48h  -- Count all procedure events (burden as activity volume)
  FROM cohort_stays cs
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.subject_id = cs.subject_id
    AND pe.hadm_id = cs.hadm_id
    AND pe.stay_id = cs.stay_id
    AND pe.starttime >= cs.intime
    AND pe.starttime < TIMESTAMP_ADD(cs.intime, INTERVAL 48 HOUR)
  GROUP BY 
    cs.stay_id, cs.subject_id, cs.hadm_id, cs.intime, cs.gender, cs.anchor_age, 
    cs.admittime, cs.dischtime, cs.hospital_expire_flag, cs.readmit_30d_flag, cs.hospital_los_days
),
quintiled_stays AS (
  -- Assign quintiles by procedure burden
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY num_procedures_48h) AS quintile
  FROM procedure_counts
)
-- Aggregate metrics per quintile
SELECT 
  quintile,
  COUNT(*) AS num_icu_stays,
  ROUND(AVG(num_procedures_48h), 2) AS mean_procedures,
  MIN(num_procedures_48h) AS min_procedures,
  MAX(num_procedures_48h) AS max_procedures,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS hospital_mortality_pct,
  ROUND(AVG(hospital_los_days), 2) AS mean_hospital_los_days,
  ROUND(AVG(readmit_30d_flag) * 100, 2) AS readmission_30d_pct
FROM quintiled_stays
GROUP BY quintile
ORDER BY quintile;