WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
),
ecg_tele_codes AS (
  SELECT
    subject_id,
    hadm_id,
    hcpcs_cd
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE
    LOWER(short_description) LIKE '%ecg%'
    OR LOWER(short_description) LIKE '%tele%'
),
patient_admission_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT e.hcpcs_cd) AS distinct_code_count
  FROM
    cohort AS c
    LEFT JOIN ecg_tele_codes AS e
      USING(subject_id, hadm_id)
  GROUP BY
    c.subject_id,
    c.hadm_id
)
SELECT
  STDDEV_POP(distinct_code_count) AS sd_distinct_ecg_telemetry_codes
FROM
  patient_admission_counts;