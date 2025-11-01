WITH pe_admissions AS (
  -- Step 1 & 2: female patients age 64–74 with a PE diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
         AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
    AND LOWER(dd.long_title) LIKE '%pulmonary embolism%'
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
),

medcount_24h AS (
  -- Step 3: count distinct drugs in the first 24h
  SELECT
    pa.subject_id,
    pa.hadm_id,
    COUNT(DISTINCT LOWER(pres.drug)) AS medcount
  FROM
    pe_admissions pa
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
      ON pa.hadm_id = pres.hadm_id
         AND pres.starttime < TIMESTAMP_ADD(pa.admittime, INTERVAL 24 HOUR)
         AND pres.stoptime > pa.admittime
  GROUP BY
    pa.subject_id,
    pa.hadm_id
),

readmissions AS (
  -- Step 4 (part 3): flag 30-day readmissions
  SELECT
    pa.subject_id,
    pa.hadm_id,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = pa.subject_id
          AND a2.admittime > pa.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(pa.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmit_30d
  FROM
    pe_admissions pa
),

combined AS (
  -- Combine all metrics
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.los_days,
    pa.hospital_expire_flag AS died_in_hosp,
    mc.medcount,
    rd.readmit_30d
  FROM
    pe_admissions pa
    LEFT JOIN medcount_24h mc
      ON pa.hadm_id = mc.hadm_id
    LEFT JOIN readmissions rd
      ON pa.hadm_id = rd.hadm_id
),

with_tertiles AS (
  -- Step 5: assign tertiles by medcount
  SELECT
    *,
    NTILE(3) OVER (ORDER BY medcount) AS med_tertile
  FROM
    combined
)

-- Step 6: summarize per tertile
SELECT
  med_tertile,
  COUNT(*) AS admissions_count,
  MIN(medcount) AS medcount_min,
  MAX(medcount) AS medcount_max,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  ROUND(100.0 * SUM(died_in_hosp) / COUNT(*), 1) AS mortality_pct,
  ROUND(100.0 * SUM(readmit_30d) / COUNT(*), 1) AS readmit_30d_pct
FROM
  with_tertiles
GROUP BY
  med_tertile
ORDER BY
  med_tertile;