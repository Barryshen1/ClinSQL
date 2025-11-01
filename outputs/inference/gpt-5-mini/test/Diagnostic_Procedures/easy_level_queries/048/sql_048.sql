WITH male_admissions AS (
  -- All hospital admissions for male patients aged 52-62 (inclusive)
  SELECT
    a.hadm_id,
    a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON a.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 52 AND 62
),

valve_procedures AS (
  -- Procedures whose description indicates valve repair or replacement
  SELECT
    p.subject_id,
    p.hadm_id,
    p.icd_code,
    p.icd_version,
    LOWER(d.long_title) AS long_title
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code
   AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%valve%'
    AND (
      LOWER(d.long_title) LIKE '%repair%'
      OR LOWER(d.long_title) LIKE '%replace%'
      OR LOWER(d.long_title) LIKE '%replacement%'
      OR LOWER(d.long_title) LIKE '%prosthesis%'
    )
),

per_admission_counts AS (
  -- Count distinct valve repair/replacement procedure codes per hospitalization.
  -- Use icd_version|icd_code to distinguish codes across ICD versions.
  SELECT
    m.hadm_id,
    COUNT(DISTINCT CONCAT(vp.icd_version, '|', vp.icd_code)) AS valve_proc_count
  FROM male_admissions m
  LEFT JOIN valve_procedures vp
    ON m.hadm_id = vp.hadm_id
  GROUP BY m.hadm_id
),

quartiles AS (
  -- APPROX_QUANTILES(...,4) returns array: [min, 25th, 50th, 75th, max]
  SELECT APPROX_QUANTILES(valve_proc_count, 4) AS q_arr
  FROM per_admission_counts
)

SELECT
  q_arr[OFFSET(1)] AS q1,
  q_arr[OFFSET(3)] AS q3,
  q_arr[OFFSET(3)] - q_arr[OFFSET(1)] AS iqr,
  (SELECT COUNT(*) FROM per_admission_counts) AS n_admissions_considered
FROM quartiles;