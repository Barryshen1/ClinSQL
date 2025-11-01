WITH patient_cohort AS (
  SELECT p.subject_id, 
         p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 78 AND 88
),
hhs_diagnoses AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code IN ('E1101', 'E1301')
),
icu_stays_hhs AS (
  SELECT DISTINCT i.stay_id, i.subject_id, i.hadm_id, i.intime, i.outtime, i.los
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN patient_cohort pc ON i.subject_id = pc.subject_id
  INNER JOIN hhs_diagnoses hhs ON i.hadm_id = hhs.hadm_id
),
vitals AS (
  SELECT ce.stay_id,
         di.label,
         ce.valuenum,
         di.lownormalvalue,
         di.highnormalvalue
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN icu_stays_hhs i
    ON ce.stay_id = i.stay_id
  WHERE ce.charttime >= i.intime
    AND ce.charttime < DATETIME_ADD(i.intime, INTERVAL 24 HOUR)
    AND di.label IN ('Heart Rate', 'Mean Blood Pressure', 'Respiratory Rate')
    AND ce.valuenum IS NOT NULL
),
vital_stats AS (
  SELECT stay_id,
         AVG(CASE WHEN label = 'Heart Rate' THEN valuenum END) AS hr_mean,
         STDDEV(CASE WHEN label = 'Heart Rate' THEN valuenum END) AS hr_std,
         AVG(CASE WHEN label = 'Mean Blood Pressure' THEN valuenum END) AS map_mean,
         STDDEV(CASE WHEN label = 'Mean Blood Pressure' THEN valuenum END) AS map_std,
         AVG(CASE WHEN label = 'Respiratory Rate' THEN valuenum END) AS rr_mean,
         STDDEV(CASE WHEN label = 'Respiratory Rate' THEN valuenum END) AS rr_std,
         COUNT(CASE WHEN label = 'Heart Rate' AND (valuenum < lownormalvalue OR valuenum > highnormalvalue) THEN 1 END) AS hr_abnormal_count,
         COUNT(CASE WHEN label = 'Mean Blood Pressure' AND (valuenum < lownormalvalue OR valuenum > highnormalvalue) THEN 1 END) AS map_abnormal_count,
         COUNT(CASE WHEN label = 'Respiratory Rate' AND (valuenum < lownormalvalue OR valuenum > highnormalvalue) THEN 1 END) AS rr_abnormal_count
  FROM vitals
  GROUP BY stay_id
),
cv_scores AS (
  SELECT stay_id,
         (CASE WHEN hr_mean > 0 THEN hr_std / hr_mean ELSE 0 END) AS hr_cv,
         (CASE WHEN map_mean > 0 THEN map_std / map_mean ELSE 0 END) AS map_cv,
         (CASE WHEN rr_mean > 0 THEN rr_std / rr_mean ELSE 0 END) AS rr_cv,
         (CASE WHEN hr_abnormal_count > 0 THEN 1 ELSE 0 END) +
         (CASE WHEN map_abnormal_count > 0 THEN 1 ELSE 0 END) +
         (CASE WHEN rr_abnormal_count > 0 THEN 1 ELSE 0 END) AS abnormal_vital_count
  FROM vital_stats
),
cohort_summary AS (
  SELECT cs.*,
         cs.hr_cv + cs.map_cv + cs.rr_cv AS cv_sum,
         i.los AS icu_los,
         a.hospital_expire_flag,
         NTILE(10) OVER (ORDER BY cs.hr_cv + cs.map_cv + cs.rr_cv) AS decile,
         NTILE(4) OVER (ORDER BY cs.hr_cv + cs.map_cv + cs.rr_cv) AS quartile
  FROM cv_scores cs
  INNER JOIN icu_stays_hhs i ON cs.stay_id = i.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON i.hadm_id = a.hadm_id
)
SELECT 
  cv_sum AS stay_instability_score,
  decile,
  abnormal_vital_count,
  icu_los,
  hospital_expire_flag AS in_hospital_mortality
FROM cohort_summary
WHERE quartile = 4
ORDER BY cv_sum DESC;