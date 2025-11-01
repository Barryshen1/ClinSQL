WITH aki_encounters AS (
  -- Identify all hospital admissions for women aged 52-62 with AKI
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions adm
    INNER JOIN physionet-data.mimiciv_3_1_hosp.patients pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd dx
      ON adm.hadm_id = dx.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 52 AND 62
    AND (
      (dx.icd_version = 9 AND dx.icd_code LIKE '584%')
      OR (dx.icd_version = 10 AND dx.icd_code LIKE 'N17%')
    )
    AND adm.dischtime IS NOT NULL
    AND adm.hospital_expire_flag = 0
),

readmissions AS (
  -- For each AKI encounter, check if there is a readmission within 30 days
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Find the next admission for the same subject after discharge
    MIN(b.admittime) AS next_admittime
  FROM
    aki_encounters a
    LEFT JOIN physionet-data.mimiciv_3_1_hosp.admissions b
      ON a.subject_id = b.subject_id
      AND b.admittime > a.dischtime
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime
),

readmission_flags AS (
  -- Flag if the next admission is within 30 days
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN next_admittime IS NOT NULL
        AND DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30
      THEN 1
      ELSE 0
    END AS readmit_30d
  FROM
    readmissions
)

-- Calculate the standard deviation of the 30-day readmission indicator across encounters
SELECT
  STDDEV(readmit_30d) AS per_encounter_30d_readmission_stddev
FROM
  readmission_flags;