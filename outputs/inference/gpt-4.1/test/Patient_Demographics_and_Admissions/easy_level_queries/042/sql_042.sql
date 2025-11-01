WITH cabg_procedures AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    MIN(a.admittime) AS first_cabg_admittime
  FROM
    physionet-data.mimiciv_3_1_hosp.procedures_icd p
    JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures d
      ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    JOIN physionet-data.mimiciv_3_1_hosp.admissions a
      ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  WHERE
    -- CABG ICD-9 codes: 36.10–36.19
    p.icd_version = 9
    AND SAFE_CAST(p.icd_code AS FLOAT64) BETWEEN 36.10 AND 36.19
  GROUP BY
    p.subject_id, p.hadm_id
),
first_cabg_admission AS (
  SELECT
    cp.subject_id,
    cp.hadm_id,
    cp.first_cabg_admittime
  FROM (
    SELECT
      subject_id,
      MIN(first_cabg_admittime) AS min_admittime
    FROM cabg_procedures
    GROUP BY subject_id
  ) min_cabg
  JOIN cabg_procedures cp
    ON cp.subject_id = min_cabg.subject_id
    AND cp.first_cabg_admittime = min_cabg.min_admittime
),
cabg_patients AS (
  SELECT
    fca.subject_id,
    fca.hadm_id,
    a.admittime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM
    first_cabg_admission fca
    JOIN physionet-data.mimiciv_3_1_hosp.admissions a
      ON fca.subject_id = a.subject_id AND fca.hadm_id = a.hadm_id
    JOIN physionet-data.mimiciv_3_1_hosp.patients p
      ON fca.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 74 AND 84
),
first_icu_stay AS (
  SELECT
    cp.subject_id,
    cp.hadm_id,
    MIN(i.intime) AS first_icu_intime
  FROM
    cabg_patients cp
    JOIN physionet-data.mimiciv_3_1_icu.icustays i
      ON cp.subject_id = i.subject_id AND cp.hadm_id = i.hadm_id
  GROUP BY
    cp.subject_id, cp.hadm_id
),
cabg_icu_los AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.los
  FROM
    physionet-data.mimiciv_3_1_icu.icustays i
    JOIN first_icu_stay fis
      ON i.subject_id = fis.subject_id
      AND i.hadm_id = fis.hadm_id
      AND i.intime = fis.first_icu_intime
)
SELECT
  COUNT(*) AS n_patients,
  ROUND(AVG(los), 2) AS mean_icu_los_days
FROM
  cabg_icu_los
;