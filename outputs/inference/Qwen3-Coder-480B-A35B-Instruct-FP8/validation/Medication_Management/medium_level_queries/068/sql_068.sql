WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
      WHERE
        (d.icd_version = 9 AND d.icd_code IN ('25000', '4280'))
        OR
        (d.icd_version = 10 AND d.icd_code IN ('E119', 'I509'))
    )
),

insulin_prescriptions AS (
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    pr.drug,
    pr.starttime,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(pr.drug), r'glargine|detemir|degludec') THEN 'basal'
      WHEN REGEXP_CONTAINS(LOWER(pr.drug), r'aspart|lispro|glulisine|regular') THEN 'bolus'
      WHEN REGEXP_CONTAINS(LOWER(pr.drug), r'basal.*bolus|bolus.*basal') THEN 'basal-bolus'
      WHEN REGEXP_CONTAINS(LOWER(pr.drug), r'sliding') THEN 'sliding-scale'
      ELSE 'other'
    END AS insulin_type
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON
    c.hadm_id = pr.hadm_id
  WHERE
    REGEXP_CONTAINS(LOWER(pr.drug), r'insulin')
    AND pr.starttime IS NOT NULL
),

first_48h AS (
  SELECT
    hadm_id,
    insulin_type,
    COUNT(DISTINCT hadm_id) AS cnt
  FROM
    insulin_prescriptions
  WHERE
    starttime <= admittime + INTERVAL 48 HOUR
    AND insulin_type IN ('basal', 'bolus', 'basal-bolus', 'sliding-scale')
  GROUP BY
    insulin_type
),

last_12h AS (
  SELECT
    hadm_id,
    insulin_type,
    COUNT(DISTINCT hadm_id) AS cnt
  FROM
    insulin_prescriptions
  WHERE
    starttime >= dischtime - INTERVAL 12 HOUR
    AND insulin_type IN ('basal', 'bolus', 'basal-bolus', 'sliding-scale')
  GROUP BY
    insulin_type
),

cohort_size AS (
  SELECT COUNT(DISTINCT hadm_id) AS total
  FROM cohort
),

first_48h_pct AS (
  SELECT
    insulin_type,
    cnt,
    ROUND(cnt * 100.0 / total, 2) AS pct
  FROM
    first_48h
  CROSS JOIN
    cohort_size
),

last_12h_pct AS (
  SELECT
    insulin_type,
    cnt,
    ROUND(cnt * 100.0 / total, 2) AS pct
  FROM
    last_12h
  CROSS JOIN
    cohort_size
)

SELECT
  COALESCE(f.insulin_type, l.insulin_type) AS insulin_type,
  COALESCE(f.pct, 0) AS first_48h_pct,
  COALESCE(l.pct, 0) AS last_12h_pct,
  COALESCE(l.pct, 0) - COALESCE(f.pct, 0) AS net_change_pct
FROM
  first_48h_pct f
FULL OUTER JOIN
  last_12h_pct l
ON
  f.insulin_type = l.insulin_type
ORDER BY
  insulin_type;