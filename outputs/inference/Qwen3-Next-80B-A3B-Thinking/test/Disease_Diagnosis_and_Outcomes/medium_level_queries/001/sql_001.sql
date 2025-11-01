WITH primary_diagnosis AS (
  SELECT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    seq_num = 1
    AND icd_code LIKE 'I50%'
),
patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) AS age_at_admission,
    MAX(CASE WHEN d2.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) OVER (PARTITION BY a.hadm_id) AS has_ckd,
    MAX(CASE WHEN d2.icd_code LIKE 'E10%' OR d2.icd_code LIKE 'E11%' THEN 1 ELSE 0 END) OVER (PARTITION BY a.hadm_id) AS has_diabetes,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = a.hadm_id
        AND i.intime >= a.admittime
        AND i.intime < a.admittime + INTERVAL '1 day'
    ) THEN 1 ELSE 0 END AS has_icu_day1
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    primary_diagnosis pd
    ON a.hadm_id = pd.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
    ON a.hadm_id = d2.hadm_id
  WHERE
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 67 AND 77
),
los_strat AS (
  SELECT
    *,
    CASE WHEN DATE_DIFF(dischtime, admittime, DAY) <= 7 THEN 'LOS<=7' ELSE 'LOS>7' END AS los_category
  FROM patient_admissions
)
SELECT
  los_category,
  has_icu_day1,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  AVG(has_ckd) * 100 AS ckd_prevalence_pct,
  AVG(has_diabetes) * 100 AS diabetes_prevalence_pct
FROM los_strat
GROUP BY los_category, has_icu_day1;