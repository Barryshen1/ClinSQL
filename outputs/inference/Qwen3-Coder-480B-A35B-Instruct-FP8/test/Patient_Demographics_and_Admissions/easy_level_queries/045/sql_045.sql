WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
),
first_icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM
    physionet-data.mimiciv_3_1_icu.icustays i
  JOIN
    first_admissions fa
  ON
    i.hadm_id = fa.hadm_id
  WHERE
    fa.rn = 1
)
SELECT
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS los_25th_percentile
FROM
  first_icu_stays
WHERE
  rn = 1;