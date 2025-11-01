WITH relevant_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.admission_type = 'EMERGENCY'
), diagnosis_filter AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM relevant_admissions AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%upper gastrointestinal bleeding%'
    AND d.seq_num = 1
), icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM diagnosis_filter AS df
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS s
    ON df.subject_id = s.subject_id AND df.hadm_id = s.hadm_id
)
SELECT
  STDDEV(s.los) AS sd_los
FROM icu_stays AS s;