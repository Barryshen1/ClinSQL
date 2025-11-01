WITH heart_failure_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE (icd_version = 10 AND icd_code LIKE 'I50%')
         OR (icd_version = 9 AND icd_code LIKE '428%')
    )
    AND p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 51 AND 61
),

icu_status AS (
  SELECT
    hfp.*,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS has_icu
  FROM
    heart_failure_patients hfp
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON hfp.hadm_id = i.hadm_id
),

los_calc AS (
  SELECT
    *,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days
  FROM
    icu_status
),

comorbidity_count AS (
  SELECT
    hfp.hadm_id,
    COUNT(d.icd_code) AS comorbidity_count
  FROM
    heart_failure_patients hfp
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON hfp.hadm_id = d.hadm_id
  WHERE
    NOT (
      (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
      OR (d.icd_version = 9 AND d.icd_code LIKE '428%')
    )
  GROUP BY
    hfp.hadm_id
),

mv_flag AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN itemid = 467 THEN 1 ELSE 0 END) AS has_mv
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents`
  GROUP BY
    hadm_id
),

vaso_flag AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN itemid IN (221906, 221902, 221907, 221662) THEN 1 ELSE 0 END) AS has_vaso
  FROM
    `physionet-data.mimiciv_3_1_icu.inputevents`
  GROUP BY
    hadm_id
),

rrt_flag AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN itemid = 227524 THEN 1 ELSE 0 END) AS has_rrt
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents`
  GROUP BY
    hadm_id
)

SELECT
  has_icu,
  CASE WHEN los_days < 8 THEN '<8' ELSE '>=8' END AS los_group,
  CASE
    WHEN comorbidity_count.comorbidity_count <= 1 THEN 'low'
    WHEN comorbidity_count.comorbidity_count BETWEEN 2 AND 3 THEN 'medium'
    ELSE 'high'
  END AS comorbidity_burden,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(COALESCE(mv_flag.has_mv, 0)) AS mv_prevalence,
  AVG(COALESCE(vaso_flag.has_vaso, 0)) AS vaso_prevalence,
  AVG(COALESCE(rrt_flag.has_rrt, 0)) AS rrt_prevalence
FROM
  los_calc
LEFT JOIN
  comorbidity_count ON los_calc.hadm_id = comorbidity_count.hadm_id
LEFT JOIN
  mv_flag ON los_calc.hadm_id = mv_flag.hadm_id
LEFT JOIN
  vaso_flag ON los_calc.hadm_id = vaso_flag.hadm_id
LEFT JOIN
  rrt_flag ON los_calc.hadm_id = rrt_flag.hadm_id
GROUP BY
  has_icu, los_group, comorbidity_burden;