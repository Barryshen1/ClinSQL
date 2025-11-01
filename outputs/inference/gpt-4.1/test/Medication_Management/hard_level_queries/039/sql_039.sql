WITH ich_admissions AS (
  -- Step 1: Identify female inpatients aged 87-97 with ICH
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
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
    AND p.anchor_age BETWEEN 87 AND 97
    AND (
      -- ICD-10 ICH: I61.x, ICD-9 ICH: 431
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I61'))
      OR (d.icd_version = 9 AND d.icd_code = '431')
    )
),

med_complexity AS (
  -- Step 2: Calculate medication complexity score in first 48h
  SELECT
    ia.subject_id,
    ia.hadm_id,
    ia.admittime,
    ia.dischtime,
    ia.deathtime,
    ia.hospital_expire_flag,
    ia.anchor_age,
    ia.gender,
    COUNT(DISTINCT CONCAT(LOWER(TRIM(pr.drug)), '|', LOWER(TRIM(pr.route)))) AS med_complexity_score
  FROM
    ich_admissions ia
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON ia.hadm_id = pr.hadm_id
      AND pr.starttime >= ia.admittime
      AND pr.starttime < DATETIME_ADD(ia.admittime, INTERVAL 48 HOUR)
      AND pr.drug IS NOT NULL
      AND pr.route IS NOT NULL
  GROUP BY
    ia.subject_id, ia.hadm_id, ia.admittime, ia.dischtime, ia.deathtime,
    ia.hospital_expire_flag, ia.anchor_age, ia.gender
),

quartiles AS (
  -- Step 3: Assign quartiles based on complexity score
  SELECT
    *,
    NTILE(4) OVER (ORDER BY med_complexity_score) AS complexity_quartile
  FROM
    med_complexity
),

los_calc AS (
  -- Step 4: Calculate LOS in days
  SELECT
    *,
    SAFE_CAST(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0 AS FLOAT64) AS los_days
  FROM
    quartiles
),

readmissions AS (
  -- Step 5: For each admission, check for 30-day readmission
  SELECT
    la.subject_id,
    la.hadm_id,
    la.dischtime,
    MIN(ra.admittime) AS next_admit_time
  FROM
    los_calc la
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ra
      ON la.subject_id = ra.subject_id
      AND ra.admittime > la.dischtime
      AND ra.admittime <= DATETIME_ADD(la.dischtime, INTERVAL 30 DAY)
  GROUP BY
    la.subject_id, la.hadm_id, la.dischtime
),

final AS (
  -- Step 6: Combine all metrics
  SELECT
    l.complexity_quartile,
    COUNT(*) AS admissions,
    MIN(l.med_complexity_score) AS min_score,
    MAX(l.med_complexity_score) AS max_score,
    APPROX_QUANTILES(l.los_days, 2)[OFFSET(1)] AS median_los_days,
    ROUND(SUM(CASE WHEN l.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS mortality_percent,
    ROUND(SUM(CASE WHEN r.next_admit_time IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS readmit_30day_percent
  FROM
    los_calc l
    LEFT JOIN readmissions r
      ON l.subject_id = r.subject_id AND l.hadm_id = r.hadm_id
  GROUP BY
    l.complexity_quartile
  ORDER BY
    l.complexity_quartile
)

SELECT
  complexity_quartile AS med_complexity_quartile,
  admissions,
  min_score,
  max_score,
  median_los_days,
  mortality_percent,
  readmit_30day_percent
FROM
  final
ORDER BY
  med_complexity_quartile;