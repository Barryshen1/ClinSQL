WITH ami_cohort AS (
  -- Define AMI cohort: males 44-54, principal AMI diagnosis, inpatients
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.anchor_age BETWEEN 44 AND 54
    AND p.gender = 'M'
    AND a.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE')
    AND d.seq_num = 1
    AND d.icd_code LIKE '410%'
    AND a.hadm_id IS NOT NULL  -- Ensure valid admission
),
first_admission AS (
  -- One admission per patient (first by admittime)
  SELECT *
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM ami_cohort
  )
  WHERE rn = 1
),
lab_instability AS (
  -- Compute instability as count of abnormal labs in first 72 hours (flag = 'abnormal')
  SELECT 
    fa.hadm_id,
    fa.admittime,
    COUNT(CASE WHEN le.flag = 'abnormal' THEN 1 END) AS abnormal_lab_count
  FROM first_admission fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON fa.subject_id = le.subject_id AND fa.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE le.charttime >= fa.admittime
    AND le.charttime <= TIMESTAMP_ADD(fa.admittime, INTERVAL 72 HOUR)
    AND le.itemid IN (50868, 50970, 50971, 51222, 51265, 5131, 225624, 50813, 50912, 50882)  -- Na, K, Cl, HCO3, BUN, Creat, WBC, Hgb, Plt, Lactate
    AND li.category IN ('Chemistry', 'Hematology', 'Blood Gas')
  GROUP BY fa.hadm_id, fa.admittime
),
critical_labs AS (
  -- Flag admissions with critical labs in first 72h
  SELECT 
    fa.hadm_id,
    MAX(
      CASE 
        WHEN le.itemid = 50971 AND le.valuenum < 3.0 THEN 1  -- Low K
        WHEN le.itemid = 50971 AND le.valuenum > 5.5 THEN 1  -- High K
        WHEN le.itemid = 50824 AND le.valuenum < 130 THEN 1  -- Low Na
        WHEN le.itemid = 50824 AND le.valuenum > 150 THEN 1  -- High Na
        WHEN le.itemid = 50912 AND le.valuenum > 2.0 THEN 1  -- High Creat
        WHEN le.itemid = 5131 AND le.valuenum > 20000 THEN 1  -- High WBC
        WHEN le.itemid = 225624 AND le.valuenum < 7.0 THEN 1  -- Low Hgb
        WHEN le.itemid = 50882 AND le.valuenum < 50000 THEN 1  -- Low Plt
        WHEN le.itemid = 50813 AND le.valuenum > 4.0 THEN 1  -- High Lactate
        ELSE 0
      END
    ) AS has_critical_lab
  FROM first_admission fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON fa.subject_id = le.subject_id AND fa.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE le.charttime >= fa.admittime
    AND le.charttime <= TIMESTAMP_ADD(fa.admittime, INTERVAL 72 HOUR)
    AND le.itemid IN (50971, 50824, 50912, 5131, 225624, 50882, 50813)
    AND le.valuenum IS NOT NULL
  GROUP BY fa.hadm_id
),
general_inpatients AS (
  -- General cohort for comparison (males 44-54, inpatients, first admission with labs)
  WITH general_cohort AS (
    SELECT 
      p.subject_id,
      a.hadm_id,
      a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    WHERE p.anchor_age BETWEEN 44 AND 54
      AND p.gender = 'M'
      AND a.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE')
  ),
  first_general AS (
    SELECT *
    FROM (
      SELECT *,
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
      FROM general_cohort
    )
    WHERE rn = 1
  )
  SELECT 
    fg.hadm_id,
    MAX(
      CASE 
        WHEN le.itemid = 50971 AND le.valuenum < 3.0 THEN 1
        WHEN le.itemid = 50971 AND le.valuenum > 5.5 THEN 1
        WHEN le.itemid = 50824 AND le.valuenum < 130 THEN 1
        WHEN le.itemid = 50824 AND le.valuenum > 150 THEN 1
        WHEN le.itemid = 50912 AND le.valuenum > 2.0 THEN 1
        WHEN le.itemid = 5131 AND le.valuenum > 20000 THEN 1
        WHEN le.itemid = 225624 AND le.valuenum < 7.0 THEN 1
        WHEN le.itemid = 50882 AND le.valuenum < 50000 THEN 1
        WHEN le.itemid = 50813 AND le.valuenum > 4.0 THEN 1
        ELSE 0
      END
    ) AS has_critical_lab_general
  FROM first_general fg
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON fg.subject_id = le.subject_id AND fg.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE le.charttime >= fg.admittime
    AND le.charttime <= TIMESTAMP_ADD(fg.admittime, INTERVAL 72 HOUR)
    AND le.itemid IN (50971, 50824, 50912, 5131, 225624, 50882, 50813)
    AND le.valuenum IS NOT NULL
  GROUP BY fg.hadm_id
)
SELECT 
  -- AMI cohort metrics
  COUNT(fa.hadm_id) AS ami_cohort_size,
  PERCENTILE_CONT(li.abnormal_lab_count, 0.75) AS p75_instability_score,
  AVG(fa.los_days) AS avg_los_days,
  SUM(fa.hospital_expire_flag) * 1.0 / COUNT(fa.hadm_id) AS mortality_rate,
  SUM(cl.has_critical_lab) * 1.0 / COUNT(fa.hadm_id) AS ami_critical_lab_freq,
  -- General comparison
  (SELECT SUM(gi.has_critical_lab_general) * 1.0 / COUNT(gi.hadm_id) FROM general_inpatients gi) AS general_critical_lab_freq
FROM first_admission fa
INNER JOIN lab_instability li ON fa.hadm_id = li.hadm_id
LEFT JOIN critical_labs cl ON fa.hadm_id = cl.hadm_id
WHERE li.abnormal_lab_count IS NOT NULL;  -- Only admissions with labs;