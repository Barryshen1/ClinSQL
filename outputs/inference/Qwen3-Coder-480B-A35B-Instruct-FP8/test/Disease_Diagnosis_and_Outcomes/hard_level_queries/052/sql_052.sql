WITH copd_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    i.stay_id,
    i.los AS icu_los,
    COALESCE(p.dod, a.deathtime) AS final_death_time
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  LEFT JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND dd.icd_code = 'J441' -- COPD exacerbation
    AND d.seq_num = 1 -- Primary diagnosis
),

first_admission AS (
  SELECT *
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM copd_admissions
  ) t
  WHERE rn = 1
),

labs_near_admission AS (
  SELECT
    fa.hadm_id,
    MAX(CASE WHEN dl.label = 'creatinine' THEN le.valuenum END) AS creatinine,
    MAX(CASE WHEN dl.label = 'bilirubin' THEN le.valuenum END) AS bilirubin,
    MAX(CASE WHEN dl.label = 'platelets' THEN le.valuenum END) AS platelets
  FROM first_admission fa
  JOIN physionet-data.mimiciv_3_1_hosp.labevents le
    ON fa.hadm_id = le.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE
    le.charttime BETWEEN fa.admittime AND DATETIME_ADD(fa.admittime, INTERVAL 24 HOUR)
    AND dl.label IN ('creatinine', 'bilirubin', 'platelets')
  GROUP BY fa.hadm_id
),

risk_score AS (
  SELECT
    fa.*,
    COALESCE(l.creatinine, 1) AS creatinine,
    COALESCE(l.bilirubin, 0.5) AS bilirubin,
    COALESCE(l.platelets, 200) AS platelets,
    CASE
      WHEN fa.anchor_age >= 80 THEN 2 ELSE 1 END +
    CASE
      WHEN l.creatinine > 1.5 THEN 1 ELSE 0 END +
    CASE
      WHEN l.bilirubin > 1 THEN 1 ELSE 0 END +
    CASE
      WHEN l.platelets < 100 THEN 1 ELSE 0 END AS risk_score
  FROM first_admission fa
  LEFT JOIN labs_near_admission l ON fa.hadm_id = l.hadm_id
),

quartiles AS (
  SELECT *,
    NTILE(4) OVER (ORDER BY
      CASE WHEN anchor_age >= 80 THEN 2 ELSE 1 END +
      CASE WHEN creatinine > 1.5 THEN 1 ELSE 0 END +
      CASE WHEN bilirubin > 1 THEN 1 ELSE 0 END +
      CASE WHEN platelets < 100 THEN 1 ELSE 0 END
    ) AS risk_quartile
  FROM risk_score
),

complications AS (
  SELECT
    q.hadm_id,
    MAX(CASE
      WHEN dd.icd_code IN ('J960', 'J969', 'J12', 'J13', 'J14', 'J15', 'J16', 'J17', 'J18')
      THEN 1 ELSE 0 END) AS major_complication
  FROM quartiles q
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON q.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE d.seq_num > 1
  GROUP BY q.hadm_id
),

outcomes AS (
  SELECT
    q.*,
    CASE
      WHEN q.final_death_time IS NOT NULL
       AND q.final_death_time <= DATETIME_ADD(q.admittime, INTERVAL 90 DAY)
      THEN 1 ELSE 0 END AS died_within_90,
    COALESCE(c.major_complication, 0) AS major_complication,
    CASE WHEN q.icu_los IS NOT NULL THEN q.icu_los ELSE DATETIME_DIFF(q.dischtime, q.admittime, DAY) END AS los_days
  FROM quartiles q
  LEFT JOIN complications c ON q.hadm_id = c.hadm_id
),

survivors AS (
  SELECT *
  FROM outcomes
  WHERE died_within_90 = 0
),

quartile_stats AS (
  SELECT
    risk_quartile,
    COUNT(*) AS n_patients,
    AVG(died_within_90) AS mortality_90,
    AVG(major_complication) AS complication_rate,
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_survivor_los
  FROM outcomes
  GROUP BY risk_quartile
),

overall_mortality AS (
  SELECT
    AVG(died_within_90) AS overall_90day_mortality
  FROM outcomes
)

SELECT
  q.risk_quartile,
  q.n_patients,
  q.mortality_90,
  q.complication_rate,
  q.median_survivor_los,
  o.overall_90day_mortality
FROM quartile_stats q
CROSS JOIN overall_mortality o
ORDER BY q.risk_quartile;