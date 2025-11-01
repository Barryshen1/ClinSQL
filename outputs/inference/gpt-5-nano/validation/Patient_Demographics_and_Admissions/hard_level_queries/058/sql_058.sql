WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
   AND di.seq_num = 1  -- principal diagnosis
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 50 AND 60
    -- ED admission source
    AND UPPER(a.admission_type) = 'EMERGENCY'
    -- Medicare insurance
    AND a.insurance LIKE '%Medicare%'
    -- principal diagnosis must correspond to lower GI bleeding
    AND LOWER(dd.long_title) LIKE '%lower%'
    AND LOWER(dd.long_title) LIKE '%gastrointestinal%'
    AND (LOWER(dd.long_title) LIKE '%bleed%' OR LOWER(dd.long_title) LIKE '%hemorrhage%')
),
calc AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS los,
    CASE
      WHEN EXISTS (
        -- any subsequent admission within 30 days after discharge
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS x
        WHERE x.subject_id = c.subject_id
          AND x.hadm_id <> c.hadm_id
          AND x.admittime > c.dischtime
          AND x.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
      ) THEN 1 ELSE 0
    END AS readmit30
  FROM cohort AS c
)
SELECT
  -- 30-day readmission rate
  100.0 * COUNTIF(readmit30 = 1) / NULLIF(COUNT(*), 0) AS readmission_rate_30d,
  -- median LOS for readmitted vs not readmitted
  (SELECT MEDIAN(los) FROM calc c2 WHERE c2.readmit30 = 1) AS median_los_readmit,
  (SELECT MEDIAN(los) FROM calc c3 WHERE c3.readmit30 = 0) AS median_los_not_readmit,
  -- percent with LOS > 6 days by readmission status
  100.0 * SAFE_DIVIDE(
            SUM(CASE WHEN readmit30 = 1 AND los > 6 THEN 1 ELSE 0 END),
            SUM(CASE WHEN readmit30 = 1 THEN 1 ELSE 0 END)
          ) AS pct_los_gt6_readmit,
  100.0 * SAFE_DIVIDE(
            SUM(CASE WHEN readmit30 = 0 AND los > 6 THEN 1 ELSE 0 END),
            SUM(CASE WHEN readmit30 = 0 THEN 1 ELSE 0 END)
          ) AS pct_los_gt6_not_readmit
FROM calc;