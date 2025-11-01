WITH cohort AS (
  -- Step 1: Identify female inpatients aged 45-55 with multi-trauma
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
  WHERE
    LOWER(p.gender) = 'female'
    AND p.anchor_age BETWEEN 45 AND 55
    AND (
      -- ICD-10 T07 (multi-trauma) or ICD-9 trauma codes (800-959)
      (d.icd_version = 10 AND d.icd_code = 'T07')
      OR
      (d.icd_version = 9 AND SAFE_CAST(d.icd_code AS INT64) BETWEEN 800 AND 959)
    )
),

meds_emar AS (
  -- Step 2a: Medications administered via EMAR in first 7 days
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT LOWER(e.medication)) AS med_complexity
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
      ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
  WHERE
    e.charttime >= c.admittime
    AND e.charttime < DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
    AND e.medication IS NOT NULL
  GROUP BY
    c.subject_id, c.hadm_id
),

meds_rx AS (
  -- Step 2b: If no EMAR, fallback to prescriptions in first 7 days
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT LOWER(r.drug)) AS med_complexity
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` r
      ON c.subject_id = r.subject_id AND c.hadm_id = r.hadm_id
  WHERE
    r.starttime >= c.admittime
    AND r.starttime < DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
    AND r.drug IS NOT NULL
  GROUP BY
    c.subject_id, c.hadm_id
),

med_complexity AS (
  -- Step 2c: Prefer EMAR, fallback to prescriptions
  SELECT
    c.subject_id,
    c.hadm_id,
    COALESCE(me.med_complexity, mr.med_complexity, 0) AS med_complexity,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag
  FROM
    cohort c
    LEFT JOIN meds_emar me
      ON c.subject_id = me.subject_id AND c.hadm_id = me.hadm_id
    LEFT JOIN meds_rx mr
      ON c.subject_id = mr.subject_id AND c.hadm_id = mr.hadm_id
),

tertile_assign AS (
  -- Step 3: Assign tertiles based on medication complexity
  SELECT
    subject_id,
    hadm_id,
    med_complexity,
    admittime,
    dischtime,
    hospital_expire_flag,
    NTILE(3) OVER (ORDER BY med_complexity) AS tertile
  FROM
    med_complexity
),

los_calc AS (
  -- Step 4a: Calculate LOS in days
  SELECT
    subject_id,
    hadm_id,
    med_complexity,
    admittime,
    dischtime,
    hospital_expire_flag,
    tertile,
    SAFE_DIVIDE(
      TIMESTAMP_DIFF(
        CAST(dischtime AS TIMESTAMP),
        CAST(admittime AS TIMESTAMP),
        SECOND
      ),
      86400
    ) AS los_days
  FROM
    tertile_assign
),

readmissions AS (
  -- Step 4b: Find 30-day readmissions for each admission
  SELECT
    a.subject_id,
    a.hadm_id,
    MIN(b.admittime) AS next_admittime
  FROM
    los_calc a
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` b
      ON a.subject_id = b.subject_id
      AND CAST(b.admittime AS TIMESTAMP) > CAST(a.dischtime AS TIMESTAMP)
  GROUP BY
    a.subject_id, a.hadm_id
),

readmit_flag AS (
  -- Step 4c: Flag admissions with 30-day readmission
  SELECT
    l.subject_id,
    l.hadm_id,
    l.tertile,
    l.med_complexity,
    l.los_days,
    l.hospital_expire_flag,
    CASE
      WHEN r.next_admittime IS NOT NULL
        AND TIMESTAMP_DIFF(
          CAST(r.next_admittime AS TIMESTAMP),
          CAST(l.dischtime AS TIMESTAMP),
          DAY
        ) <= 30
      THEN 1 ELSE 0
    END AS readmit_30d
  FROM
    los_calc l
    LEFT JOIN readmissions r
      ON l.subject_id = r.subject_id AND l.hadm_id = r.hadm_id
)

-- Final aggregation per tertile
SELECT
  tertile,
  COUNT(*) AS admissions,
  ROUND(AVG(med_complexity),1) AS mean_med_complexity,
  MIN(med_complexity) AS min_med_complexity,
  MAX(med_complexity) AS max_med_complexity,
  ROUND(AVG(los_days),2) AS mean_los_days,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_percent,
  ROUND(100.0 * SUM(readmit_30d) / COUNT(*), 2) AS readmit_30d_percent
FROM
  readmit_flag
GROUP BY
  tertile
ORDER BY
  tertile;