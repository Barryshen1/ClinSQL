WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    IF(icustay.hadm_id IS NOT NULL, 1, 0) AS icu_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  LEFT JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icustay
  ON a.hadm_id = icustay.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 71 AND 81
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'T8%'
    )
),
quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (PARTITION BY icu_flag ORDER BY los_days) AS los_quartile
  FROM cohort
),
interventions AS (
  SELECT
    pe.hadm_id,
    MAX(CASE WHEN di.label LIKE '%Ventilation%' OR di.category LIKE '%Ventilation%' THEN 1 ELSE 0 END) AS mech_vent,
    MAX(CASE WHEN di.label LIKE '%Norepinephrine%' OR di.label LIKE '%Epinephrine%' OR di.label LIKE '%Phenylephrine%' OR di.label LIKE '%Vasopressin%' THEN 1 ELSE 0 END) AS vasopressors,
    MAX(CASE WHEN di.label LIKE '%Dialysis%' OR di.category LIKE '%Renal%' THEN 1 ELSE 0 END) AS rrt
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  FULL OUTER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON pe.hadm_id = ie.hadm_id
  FULL OUTER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe2
    ON pe.hadm_id = pe2.hadm_id
  GROUP BY pe.hadm_id
),
cohort_with_int AS (
  SELECT
    q.*,
    IFNULL(interv.mech_vent,0) AS mech_vent,
    IFNULL(interv.vasopressors,0) AS vasopressors,
    IFNULL(interv.rrt,0) AS rrt
  FROM quartiles q
  LEFT JOIN interventions interv
    ON q.hadm_id = interv.hadm_id
),
stats AS (
  SELECT
    icu_flag,
    los_quartile,
    COUNT(*) AS n_adm,
    SUM(hospital_expire_flag) AS deaths,
    AVG(hospital_expire_flag)*100 AS mortality_pct,
    AVG(mech_vent)*100 AS mech_vent_pct,
    AVG(vasopressors)*100 AS vasopressors_pct,
    AVG(rrt)*100 AS rrt_pct
  FROM cohort_with_int
  GROUP BY icu_flag, los_quartile
),
q1_baseline AS (
  SELECT
    icu_flag,
    mortality_pct AS q1_mortality
  FROM stats
  WHERE los_quartile = 1
)
SELECT
  s.icu_flag,
  s.los_quartile,
  s.n_adm,
  s.deaths,
  ROUND(s.mortality_pct,1) AS mortality_pct,
  ROUND(s.mortality_pct - q1.q1_mortality,1) AS abs_diff_vs_q1,
  ROUND(s.mortality_pct / NULLIF(q1.q1_mortality,0),2) AS rel_ratio_vs_q1,
  ROUND(s.mech_vent_pct,1) AS mech_vent_pct,
  ROUND(s.vasopressors_pct,1) AS vasopressors_pct,
  ROUND(s.rrt_pct,1) AS rrt_pct
FROM stats s
JOIN q1_baseline q1
  ON s.icu_flag = q1.icu_flag
ORDER BY s.icu_flag, s.los_quartile;