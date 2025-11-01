WITH pneumonia_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%pneumonia%'
    AND p.gender = 'M'
    AND p.anchor_age >= 43
    AND p.anchor_age <= 53
),
first_icustay AS (
  SELECT pa.subject_id, pa.hadm_id, MIN(i.intime) AS first_intime
  FROM pneumonia_admissions pa
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON i.subject_id = pa.subject_id AND i.hadm_id = pa.hadm_id
  GROUP BY pa.subject_id, pa.hadm_id
),
first_los AS (
  SELECT i.los
  FROM first_icustay fi
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON i.subject_id = fi.subject_id
   AND i.hadm_id = fi.hadm_id
  AND i.intime = fi.first_intime
)
SELECT q[OFFSET(1)] AS p25_icu_los_days
FROM (
  SELECT APPROX_QUANTILES(los, 4) AS q
  FROM first_los
);