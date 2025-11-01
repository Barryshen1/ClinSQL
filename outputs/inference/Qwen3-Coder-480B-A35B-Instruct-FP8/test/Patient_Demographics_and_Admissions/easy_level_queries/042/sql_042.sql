WITH cabg_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
      ON p.subject_id = a.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd proc
      ON a.hadm_id = proc.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dproc
      ON proc.icd_code = dproc.icd_code
      AND proc.icd_version = dproc.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND (
      LOWER(dproc.long_title) LIKE '%coronary artery bypass%'
      OR LOWER(dproc.long_title) LIKE '%cabg%'
    )
),
first_cabg_admissions AS (
  SELECT
    subject_id,
    hadm_id
  FROM
    cabg_admissions
  WHERE
    rn = 1
)
SELECT
  AVG(icu.los) AS mean_icu_los_days
FROM
  first_cabg_admissions fca
JOIN
  physionet-data.mimiciv_3_1_icu.icustays icu
    ON fca.hadm_id = icu.hadm_id;