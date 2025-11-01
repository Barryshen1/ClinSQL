WITH hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    USING(subject_id, hadm_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND LOWER(dd.long_title) LIKE '%heart failure%'
),
first_hf AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM
    hf_admissions
)
SELECT
  AVG(has_readmission) AS avg_30d_readmission_rate
FROM (
  SELECT
    f.subject_id,
    f.hadm_id,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM
          `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
        WHERE
          a2.subject_id = f.subject_id
          AND a2.admittime > f.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(f.dischtime, INTERVAL 30 DAY)
      )
      THEN 1
      ELSE 0
    END AS has_readmission
  FROM
    first_hf AS f
  WHERE
    f.rn = 1
) AS readmit_flags;