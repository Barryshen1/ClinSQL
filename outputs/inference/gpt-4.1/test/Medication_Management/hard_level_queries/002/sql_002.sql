WITH ami_admissions AS (
  -- Step 1: Identify male patients aged 67-77 with AMI
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
    JOIN physionet-data.mimiciv_3_1_hosp.patients p
      ON a.subject_id = p.subject_id
    JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      ON a.hadm_id = d.hadm_id
    JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND (
      -- ICD-10 AMI: I21.x, I22.x; ICD-9 AMI: 410.x
      (d.icd_version = 10 AND (dd.icd_code LIKE 'I21%' OR dd.icd_code LIKE 'I22%'))
      OR
      (d.icd_version = 9 AND dd.icd_code LIKE '410%')
    )
),
med_complexity AS (
  -- Step 2: Compute first-24h medication complexity score per admission
  SELECT
    aa.subject_id,
    aa.hadm_id,
    COUNT(DISTINCT LOWER(e.medication)) AS complexity_score
  FROM
    ami_admissions aa
    LEFT JOIN physionet-data.mimiciv_3_1_hosp.emar e
      ON aa.subject_id = e.subject_id AND aa.hadm_id = e.hadm_id
      AND e.charttime >= aa.admittime
      AND e.charttime < TIMESTAMP_ADD(aa.admittime, INTERVAL 24 HOUR)
  GROUP BY
    aa.subject_id, aa.hadm_id
),
admission_with_score AS (
  -- Step 3: Join back to get LOS, mortality, etc.
  SELECT
    mc.subject_id,
    mc.hadm_id,
    mc.complexity_score,
    aa.admittime,
    aa.dischtime,
    aa.hospital_expire_flag,
    -- LOS in days
    SAFE_DIVIDE(TIMESTAMP_DIFF(aa.dischtime, aa.admittime, SECOND), 86400) AS los_days
  FROM
    med_complexity mc
    JOIN ami_admissions aa
      ON mc.subject_id = aa.subject_id AND mc.hadm_id = aa.hadm_id
),
tertile_assign AS (
  -- Step 4: Assign tertiles by complexity score
  SELECT
    *,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM
    admission_with_score
),
readmissions AS (
  -- Step 5: For each admission, check for 30-day readmission
  SELECT
    t.subject_id,
    t.hadm_id,
    t.dischtime,
    -- Is there another admission for same subject within 30 days after discharge?
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM physionet-data.mimiciv_3_1_hosp.admissions a2
        WHERE
          a2.subject_id = t.subject_id
          AND a2.admittime > t.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(t.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmit_30d
  FROM
    tertile_assign t
)
SELECT
  tertile,
  COUNT(*) AS admission_count,
  MIN(complexity_score) AS score_min,
  MAX(complexity_score) AS score_max,
  ROUND(AVG(complexity_score),2) AS score_mean,
  ROUND(AVG(los_days),2) AS mean_los_days,
  ROUND(100 * AVG(CAST(hospital_expire_flag AS FLOAT64)),2) AS in_hosp_mortality_pct,
  ROUND(100 * AVG(CAST(r.readmit_30d AS FLOAT64)),2) AS readmit_30d_pct
FROM
  tertile_assign t
  JOIN readmissions r
    ON t.subject_id = r.subject_id AND t.hadm_id = r.hadm_id
GROUP BY
  tertile
ORDER BY
  tertile;