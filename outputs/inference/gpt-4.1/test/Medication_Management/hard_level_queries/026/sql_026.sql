WITH pneumonia_admissions AS (
  -- Step 1: Identify female inpatients aged 76–86 with pneumonia
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND (
      -- ICD-10 pneumonia: J12-J18
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^J1[2-8]'))
      -- ICD-9 pneumonia: 480-486
      OR (d.icd_version = 9 AND SAFE_CAST(d.icd_code AS INT64) BETWEEN 480 AND 486)
    )
),
med_complexity AS (
  -- Step 2: Calculate medication complexity score for each admission
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.hospital_expire_flag,
    COUNT(DISTINCT pr.drug) AS med_complexity
  FROM
    pneumonia_admissions pa
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON pa.hadm_id = pr.hadm_id
      AND pr.starttime >= pa.admittime
      AND pr.starttime < DATETIME_ADD(pa.admittime, INTERVAL 7 DAY)
  GROUP BY
    pa.subject_id, pa.hadm_id, pa.admittime, pa.dischtime, pa.hospital_expire_flag
),
tertiles AS (
  -- Step 3: Compute tertile cutoffs (fix: use column, not struct)
  SELECT
    APPROX_QUANTILES(med_complexity, 3) AS cuts
  FROM
    med_complexity
),
med_with_tertile AS (
  -- Step 3b: Assign tertile to each admission
  SELECT
    mc.*,
    CASE
      WHEN mc.med_complexity <= t.cuts[OFFSET(1)] THEN 'Low'
      WHEN mc.med_complexity <= t.cuts[OFFSET(2)] THEN 'Medium'
      ELSE 'High'
    END AS tertile
  FROM
    med_complexity mc
    CROSS JOIN tertiles t
),
readmissions AS (
  -- Step 4: For each admission, check if patient is readmitted within 30 days
  SELECT
    mwt.subject_id,
    mwt.hadm_id,
    MIN(a2.admittime) AS next_admit
  FROM
    med_with_tertile mwt
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
      ON mwt.subject_id = a2.subject_id
      AND a2.admittime > mwt.dischtime
      AND a2.admittime <= DATETIME_ADD(mwt.dischtime, INTERVAL 30 DAY)
  GROUP BY
    mwt.subject_id, mwt.hadm_id
),
final AS (
  -- Step 5: Aggregate stats by tertile
  SELECT
    tertile,
    COUNT(*) AS admission_count,
    MIN(med_complexity) AS min_med_complexity,
    AVG(med_complexity) AS avg_med_complexity,
    MAX(med_complexity) AS max_med_complexity,
    AVG(TIMESTAMP_DIFF(CAST(dischtime AS TIMESTAMP), CAST(admittime AS TIMESTAMP), DAY)) AS mean_los_days,
    100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS in_hospital_mortality_pct,
    100.0 * SUM(CASE WHEN r.next_admit IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS readmit_30day_pct
  FROM
    med_with_tertile mwt
    LEFT JOIN readmissions r
      ON mwt.subject_id = r.subject_id AND mwt.hadm_id = r.hadm_id
  GROUP BY
    tertile
  ORDER BY
    CASE tertile
      WHEN 'Low' THEN 1
      WHEN 'Medium' THEN 2
      WHEN 'High' THEN 3
      ELSE 4
    END
)
SELECT * FROM final;