WITH pneumonia_adult_males AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.los AS icu_los,
    a.hospital_expire_flag,
    i.intime AS icu_intime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND (
      dd.icd_code LIKE 'J18%' OR
      dd.icd_code = '486'
    )
),

meds_first_24hr AS (
  SELECT
    iv.stay_id,
    COUNT(DISTINCT iv.itemid) AS med_count
  FROM
    `physionet-data.mimiciv_3_1_icu.inputevents` iv
  JOIN
    pneumonia_adult_males p
  ON
    iv.stay_id = p.stay_id
  WHERE
    DATETIME_DIFF(iv.starttime, p.icu_intime, HOUR) BETWEEN 0 AND 24
  GROUP BY
    iv.stay_id
),

patients_with_meds AS (
  SELECT
    p.*,
    COALESCE(m.med_count, 0) AS med_count
  FROM
    pneumonia_adult_males p
  LEFT JOIN
    meds_first_24hr m
  ON
    p.stay_id = m.stay_id
  WHERE
    m.med_count > 0
),

serotonergic_drugs AS (
  SELECT DISTINCT
    e.subject_id,
    e.hadm_id,
    e.emar_id,
    e.medication
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar` e
  WHERE
    REGEXP_CONTAINS(UPPER(e.medication), r'SERTRALINE|FLUOXETINE|PAROXETINE|CITALOPRAM|ESCITALOPRAM|VENLAFAXINE|DESVENLAFAXINE|DULOXETINE|BUPROPION|TRAZODONE|MAOI|LINEZOLID|TRAMADOL|MEPERIDINE|FENTANYL')
),

serotonergic_patients AS (
  SELECT DISTINCT
    p.stay_id
  FROM
    patients_with_meds p
  JOIN
    serotonergic_drugs s
  ON
    p.hadm_id = s.hadm_id
),

patients_labeled AS (
  SELECT
    p.*,
    CASE WHEN s.stay_id IS NOT NULL THEN 1 ELSE 0 END AS serotonergic_risk
  FROM
    patients_with_meds p
  LEFT JOIN
    serotonergic_patients s
  ON
    p.stay_id = s.stay_id
),

quartiles AS (
  SELECT
    APPROX_QUANTILES(icu_los, 4) AS los_quartiles,
    APPROX_QUANTILES(med_count, 4) AS med_quartiles
  FROM
    patients_labeled
),

patients_with_quartiles AS (
  SELECT
    p.*,
    q.los_quartiles[ORDINAL(4)] AS los_q3,
    q.med_quartiles[ORDINAL(4)] AS med_q3
  FROM
    patients_labeled p
  CROSS JOIN
    quartiles q
),

final_stats AS (
  SELECT
    serotonergic_risk,
    AVG(med_count) AS mean_med_count,
    APPROX_QUANTILES(med_count, 4)[ORDINAL(2)] AS p25_med_count,
    APPROX_QUANTILES(med_count, 4)[ORDINAL(3)] AS p50_med_count,
    APPROX_QUANTILES(med_count, 4)[ORDINAL(4)] AS p75_med_count,
    AVG(icu_los) AS mean_los,
    AVG(hospital_expire_flag) AS mortality_rate,
    COUNT(*) AS patient_count,
    COUNTIF(icu_los >= los_q3) AS top_quartile_los_count,
    COUNTIF(hospital_expire_flag = 1) AS mortality_count,
    COUNTIF(hospital_expire_flag = 1 AND icu_los >= los_q3) AS top_quartile_mortality_count
  FROM
    patients_with_quartiles
  GROUP BY
    serotonergic_risk
)

SELECT
  serotonergic_risk,
  mean_med_count,
  p25_med_count,
  p50_med_count,
  p75_med_count,
  mean_los,
  mortality_rate,
  patient_count,
  top_quartile_los_count,
  mortality_count,
  top_quartile_mortality_count
FROM
  final_stats
ORDER BY
  serotonergic_risk;