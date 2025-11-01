WITH cabg_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS cabg_adm_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pc
      ON a.subject_id = pc.subject_id
     AND a.hadm_id    = pc.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON pc.icd_code    = dp.icd_code
     AND pc.icd_version = dp.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND pc.icd_version = 9
    AND pc.icd_code >= '36.10'
    AND pc.icd_code <  '36.20'
),
first_cabg_admissions AS (
  SELECT
    subject_id,
    hadm_id
  FROM
    cabg_admissions
  WHERE
    cabg_adm_rank = 1
),
first_icustays AS (
  SELECT
    fca.subject_id,
    fca.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los,
    ROW_NUMBER() OVER (PARTITION BY fca.subject_id ORDER BY icu.intime) AS icu_rank
  FROM
    first_cabg_admissions fca
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON fca.subject_id = icu.subject_id
     AND fca.hadm_id    = icu.hadm_id
)
SELECT
  AVG(icu.los) AS mean_icu_los_days
FROM
  first_icustays icu
WHERE
  icu.icu_rank = 1;