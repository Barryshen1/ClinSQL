WITH patients_filtered AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 55 AND 65
),

cardiac_arrest_admissions AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (di.icd_version = 9 AND di.icd_code = '4275')
     OR (di.icd_version = 10 AND di.icd_code LIKE 'I46%')
),

cohort_stays AS (
  SELECT istay.stay_id, istay.hadm_id, istay.intime, istay.los
  FROM `physionet-data.mimiciv_3_1_icu`.icustays istay
  INNER JOIN patients_filtered pf ON istay.subject_id = pf.subject_id
  INNER JOIN cardiac_arrest_admissions ca ON istay.hadm_id = ca.hadm_id
),

vital_signs_abnormal AS (
  SELECT ce.stay_id,
         COUNT(*) AS instability_score
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN cohort_stays cs
    ON ce.stay_id = cs.stay_id
  WHERE ce.charttime >= cs.intime
    AND ce.charttime < DATETIME_ADD(cs.intime, INTERVAL 24 HOUR)
    AND di.category = 'Vital Signs'
    AND ce.valuenum IS NOT NULL
    AND di.lownormalvalue IS NOT NULL
    AND di.highnormalvalue IS NOT NULL
    AND (ce.valuenum < di.lownormalvalue OR ce.valuenum > di.highnormalvalue)
  GROUP BY ce.stay_id
),

score_distribution AS (
  SELECT vsa.instability_score,
         CUME_DIST() OVER (ORDER BY vsa.instability_score) AS cume_dist
  FROM vital_signs_abnormal vsa
),

percentile_of_70 AS (
  SELECT COALESCE(MAX(cume_dist), 0) * 100 AS percentile_of_70
  FROM score_distribution
  WHERE instability_score <= 70
),

ranked_stays AS (
  SELECT vsa.stay_id, vsa.instability_score,
         PERCENT_RANK() OVER (ORDER BY vsa.instability_score) AS pct_rank
  FROM vital_signs_abnormal vsa
),

top_decile AS (
  SELECT rs.stay_id
  FROM ranked_stays rs
  WHERE rs.pct_rank >= 0.9
),

top_decile_outcomes AS (
  SELECT 
    AVG(istay.los) AS mean_los_top_decile,
    AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS mortality_top_decile
  FROM top_decile td
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays istay
    ON td.stay_id = istay.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON istay.hadm_id = a.hadm_id
)

SELECT 
  (SELECT percentile_of_70 FROM percentile_of_70) AS percentile_of_70,
  (SELECT mean_los_top_decile FROM top_decile_outcomes) AS mean_los_top_decile,
  (SELECT mortality_top_decile FROM top_decile_outcomes) AS mortality_top_decile;