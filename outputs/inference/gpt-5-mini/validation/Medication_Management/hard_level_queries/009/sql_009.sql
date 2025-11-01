WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '584%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
        )
    )
),

-- All prescriptions for cohort admissions, with admission window attached
presc AS (
  SELECT
    p.hadm_id,
    p.drug,
    p.starttime,
    p.stoptime,
    c.admittime,
    c.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    cohort c
  USING(hadm_id)
),

-- Medication complexity: count distinct drug names per admission
med_counts AS (
  SELECT
    co.hadm_id,
    COALESCE(mc.med_count, 0) AS med_count,
    co.admittime,
    co.dischtime,
    co.subject_id,
    co.hospital_expire_flag
  FROM
    cohort co
  LEFT JOIN (
    SELECT
      hadm_id,
      COUNT(DISTINCT LOWER(drug)) AS med_count
    FROM presc
    WHERE drug IS NOT NULL
    GROUP BY hadm_id
  ) mc
  USING(hadm_id)
),

-- Identify admissions with anticoagulant-opioid overlapping prescriptions
coadmin_hadm AS (
  SELECT DISTINCT
    p1.hadm_id
  FROM
    presc p1
  JOIN
    presc p2
  USING(hadm_id)
  WHERE
    -- p1 qualifies as anticoagulant, p2 as opioid
    REGEXP_CONTAINS(LOWER(COALESCE(p1.drug, '')), '\\b(heparin|warfarin|enoxaparin|dabigatran|apixaban|rivaroxaban|fondaparinux|bivalirudin|argatroban)\\b')
    AND REGEXP_CONTAINS(LOWER(COALESCE(p2.drug, '')), '\\b(morphine|hydromorphone|oxycodone|fentanyl|methadone|codeine|tramadol|hydrocodone|meperidine|oxymorphone)\\b')
    -- temporal overlap: [start1,end1] intersects [start2,end2]
    AND (
      COALESCE(p1.starttime, p1.admittime) <= COALESCE(p2.stoptime, p2.dischtime)
      AND COALESCE(p2.starttime, p2.admittime) <= COALESCE(p1.stoptime, p1.dischtime)
    )
),

-- Readmit within 30 days flag per admission
readmit30_flag AS (
  SELECT
    c.hadm_id,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = c.subject_id
        AND a2.hadm_id != c.hadm_id
        AND a2.admittime > c.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
    ) AS readmit30
  FROM cohort c
),

-- Combine per-admission metrics, compute quintile by med_count
per_admission AS (
  SELECT
    m.hadm_id,
    m.subject_id,
    m.admittime,
    m.dischtime,
    m.hospital_expire_flag,
    m.med_count,
    CASE WHEN r.readmit30 THEN 1 ELSE 0 END AS readmit30_flag,
    CASE WHEN cdh.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS coadmin_flag
  FROM
    med_counts m
  LEFT JOIN
    readmit30_flag r
  USING(hadm_id)
  LEFT JOIN
    coadmin_hadm cdh
  USING(hadm_id)
),

-- Assign quintiles across the cohort by med_count
with_quintile AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY med_count) AS med_complexity_quintile
  FROM per_admission
)

-- Final aggregation by quintile
SELECT
  med_complexity_quintile AS quintile,
  COUNT(*) AS admissions_in_quintile,
  ROUND(AVG(SAFE_DIVIDE(TIMESTAMP_DIFF(dischtime, admittime, MINUTE), 1440.0)), 2) AS mean_los_days,
  ROUND(100.0 * SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)), 2) AS inpatient_mortality_pct,
  ROUND(100.0 * SAFE_DIVIDE(SUM(readmit30_flag), COUNT(*)), 2) AS readmit_30day_pct,
  SUM(coadmin_flag) AS anticoag_opioid_coadministration_admission_count,
  ROUND(AVG(med_count),2) AS avg_med_count_in_quintile
FROM
  with_quintile
GROUP BY
  med_complexity_quintile
ORDER BY
  med_complexity_quintile;