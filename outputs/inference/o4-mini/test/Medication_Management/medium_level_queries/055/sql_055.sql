WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes mellitus, type 2%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
    )
),
insulin_flags AS (
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    -- First 72h window
    MAX(CASE
      WHEN p.starttime BETWEEN c.admittime 
                         AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
       AND (
         LOWER(p.drug) LIKE '%glargine%'
      OR LOWER(p.drug) LIKE '%detemir%'
      OR LOWER(p.drug) LIKE '%nph%'
       )
      THEN 1 ELSE 0 END) AS f72_has_basal,
    MAX(CASE
      WHEN p.starttime BETWEEN c.admittime 
                         AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
       AND (
         LOWER(p.drug) LIKE '%lispro%'
      OR LOWER(p.drug) LIKE '%aspart%'
      OR LOWER(p.drug) LIKE '%regular insulin%'
       )
      THEN 1 ELSE 0 END) AS f72_has_bolus,
    MAX(CASE
      WHEN p.starttime BETWEEN c.admittime 
                         AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
       AND LOWER(p.drug) LIKE '%sliding%'
      THEN 1 ELSE 0 END) AS f72_has_sliding,
    -- Final 48h window
    MAX(CASE
      WHEN p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR)
                         AND c.dischtime
       AND (
         LOWER(p.drug) LIKE '%glargine%'
      OR LOWER(p.drug) LIKE '%detemir%'
      OR LOWER(p.drug) LIKE '%nph%'
       )
      THEN 1 ELSE 0 END) AS l48_has_basal,
    MAX(CASE
      WHEN p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR)
                         AND c.dischtime
       AND (
         LOWER(p.drug) LIKE '%lispro%'
      OR LOWER(p.drug) LIKE '%aspart%'
      OR LOWER(p.drug) LIKE '%regular insulin%'
       )
      THEN 1 ELSE 0 END) AS l48_has_bolus,
    MAX(CASE
      WHEN p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR)
                         AND c.dischtime
       AND LOWER(p.drug) LIKE '%sliding%'
      THEN 1 ELSE 0 END) AS l48_has_sliding
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON c.hadm_id = p.hadm_id
  GROUP BY
    c.hadm_id,
    c.admittime,
    c.dischtime
),
regimens AS (
  SELECT
    hadm_id,
    CASE
      WHEN f72_has_basal = 1 AND f72_has_bolus = 1 THEN 'basal_bolus'
      WHEN f72_has_basal = 1 THEN 'basal'
      WHEN f72_has_bolus = 1 THEN 'bolus'
      WHEN f72_has_sliding = 1 THEN 'sliding_scale'
      ELSE 'none'
    END AS freq72_regimen,
    CASE
      WHEN l48_has_basal = 1 AND l48_has_bolus = 1 THEN 'basal_bolus'
      WHEN l48_has_basal = 1 THEN 'basal'
      WHEN l48_has_bolus = 1 THEN 'bolus'
      WHEN l48_has_sliding = 1 THEN 'sliding_scale'
      ELSE 'none'
    END AS last48_regimen
  FROM
    insulin_flags
),
totals AS (
  SELECT
    COUNT(*) AS cohort_n
  FROM
    cohort
)
SELECT
  regimen,
  ROUND(
    100.0 * SUM(CASE WHEN freq72_regimen = regimen THEN 1 ELSE 0 END)
    / ANY_VALUE(t.cohort_n)
  , 1) AS pct_first_72h,
  ROUND(
    100.0 * SUM(CASE WHEN last48_regimen = regimen THEN 1 ELSE 0 END)
    / ANY_VALUE(t.cohort_n)
  , 1) AS pct_final_48h,
  ROUND(
    100.0 * SUM(CASE WHEN last48_regimen = regimen THEN 1 ELSE 0 END)
    / ANY_VALUE(t.cohort_n)
    - 100.0 * SUM(CASE WHEN freq72_regimen = regimen THEN 1 ELSE 0 END)
      / ANY_VALUE(t.cohort_n)
  , 1) AS pct_point_diff
FROM
  regimens x
  CROSS JOIN UNNEST(['none','basal','bolus','basal_bolus','sliding_scale']) AS regimen
  CROSS JOIN totals t
GROUP BY
  regimen
ORDER BY
  regimen;