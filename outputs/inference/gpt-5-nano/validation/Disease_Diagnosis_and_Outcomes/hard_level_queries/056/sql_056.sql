WITH
base_males AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
),
dx_counts AS (
  SELECT hadm_id, COUNT(*) AS dx_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
septic_hadm AS (
  -- hadm with septic/sepsis keywords and >15 diagnoses
  SELECT b.subject_id, b.hadm_id, b.admittime, b.dischtime, b.deathtime, dc.dx_count
  FROM base_males AS b
  JOIN dx_counts AS dc ON b.hadm_id = dc.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.hadm_id = b.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%sepsis%'
     OR LOWER(dd.long_title) LIKE '%septic%'
     OR LOWER(dd.long_title) LIKE '% septicemia%'
  GROUP BY b.subject_id, b.hadm_id, b.admittime, b.dischtime, b.deathtime, dc.dx_count
  HAVING dc.dx_count > 15
),
-- 2) Charlson-like risk score per subject (simplified mapping from long_title)
-- Build per-subject booleans for the Charlson conditions, restricted to septic_hadm diagnoses
char_flags AS (
  SELECT s.subject_id,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%myocardial infarction%' THEN 1 ELSE 0 END) AS mi,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%congestive heart failure%' THEN 1 ELSE 0 END) AS chf,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%peripheral vascular disease%' THEN 1 ELSE 0 END) AS pvd,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%cerebrovascular%' THEN 1 ELSE 0 END) AS cva,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%dementia%' THEN 1 ELSE 0 END) AS dementia,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%chronic pulmonary disease%' THEN 1 ELSE 0 END) AS copd,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes without%' THEN 1 ELSE 0 END) AS diabetes_no_comp,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes with%' THEN 1 ELSE 0 END) AS diabetes_with_comp,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%peptic ulcer%' THEN 1 ELSE 0 END) AS peptic_ulcer,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%liver disease%' THEN 1 ELSE 0 END) AS liver_disease,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%renal%' OR LOWER(dd.long_title) LIKE '%kidney%' THEN 1 ELSE 0 END) AS renal_disease,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%metastatic solid tumor%' THEN 1 ELSE 0 END) AS metastatic_solid_tumor,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%solid tumor%' AND LOWER(dd.long_title) NOT LIKE '%metastatic%' THEN 1 ELSE 0 END) AS solid_tumor,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%leukemia%' THEN 1 ELSE 0 END) AS leukemia,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%lymphoma%' THEN 1 ELSE 0 END) AS lymphoma,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%AIDS%' OR LOWER(dd.long_title) LIKE '%HIV%' THEN 1 ELSE 0 END) AS aids
  FROM septic_hadm AS s
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.hadm_id = s.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  GROUP BY s.subject_id
),
char_score AS (
  SELECT t.subject_id,
         (mi*1)  + (chf*1) + (pvd*1) + (cva*1) + (dementia*1)
         + (copd*1) + (diabetes_no_comp*1) + (diabetes_with_comp*2)
         + (peptic_ulcer*1) + (liver_disease*1) + (renal_disease*2)
         + (metastatic_solid_tumor*6) + (solid_tumor*2)
         + (leukemia*2) + (lymphoma*2) + (aids*6) AS charlson_score
  FROM (
    SELECT subject_id,
           MAX(mi) AS mi, MAX(chf) AS chf, MAX(pvd) AS pvd, MAX(cva) AS cva, MAX(dementia) AS dementia,
           MAX(copd) AS copd, MAX(diabetes_no_comp) AS diabetes_no_comp, MAX(diabetes_with_comp) AS diabetes_with_comp,
           MAX(peptic_ulcer) AS peptic_ulcer, MAX(liver_disease) AS liver_disease, MAX(renal_disease) AS renal_disease,
           MAX(metastatic_solid_tumor) AS metastatic_solid_tumor, MAX(solid_tumor) AS solid_tumor,
           MAX(leukemia) AS leukemia, MAX(lymphoma) AS lymphoma, MAX(aids) AS aids
    FROM char_flags
    GROUP BY subject_id
  ) AS t
),
-- 3) Major complications per hadm (within septic_hadm cohort)
major_comp_per_hadm AS (
  SELECT s.hadm_id,
         MAX(CASE
               WHEN LOWER(dd.long_title) LIKE '%acute renal failure%' THEN 1
               WHEN LOWER(dd.long_title) LIKE '%respiratory failure%' THEN 1
               WHEN LOWER(dd.long_title) LIKE '%shock%' THEN 1
               WHEN LOWER(dd.long_title) LIKE '%septic shock%' THEN 1
               WHEN LOWER(dd.long_title) LIKE '%sepsis%' THEN 1
               ELSE 0
             END) AS major_comp
  FROM septic_hadm AS s
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di ON di.hadm_id = s.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  GROUP BY s.hadm_id
),
-- 4) Assemble septic metrics per hadm
septic_metrics AS (
  SELECT s.subject_id, s.hadm_id,
         s.admittime, s.dischtime, s.deathtime,
         c.charlson_score,
         COALESCE(m.major_comp, 0) AS major_comp,
         DATE(s.dischtime) - DATE(s.admittime) AS LOS_days,
         CASE WHEN s.deathtime IS NOT NULL
                   AND DATE_DIFF(DATE(s.deathtime), DATE(s.admittime), DAY) <= 90
              THEN 1 ELSE 0 END AS death_90
  FROM septic_hadm AS s
  LEFT JOIN char_score AS c ON s.subject_id = c.subject_id
  LEFT JOIN major_comp_per_hadm AS m ON s.hadm_id = m.hadm_id
),
-- 5) Profile admissions: anchor_age 68 male with septic_hadm and exactly 16 diagnoses
profile_hadm AS (
  SELECT s.subject_id, s.hadm_id, s.admittime, s.dischtime, s.deathtime
  FROM septic_hadm AS s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON s.subject_id = p.subject_id
  JOIN dx_counts AS dc ON s.hadm_id = dc.hadm_id
  WHERE p.anchor_age = 68
    AND p.gender = 'M'
    AND dc.dx_count = 16
),
-- 6) Profile LOS (average across profile hadms)
profile_los AS (
  SELECT AVG(DATE(dischtime) - DATE(admittime)) AS profile_avg_los_days
  FROM (
    SELECT ph.hadm_id, ph.admittime, ph.dischtime
    FROM profile_hadm AS ph
  ) AS t
),
-- 7) General survivors LOS distribution (for percentile)
general_survivors AS (
  SELECT DATE(dischtime) - DATE(admittime) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE a.deathtime IS NULL
),
-- 8) Major_comp_rate_general (all admissions baseline)
major_comp_general AS (
  SELECT AVG(CASE WHEN ddm.major_comp = 1 THEN 1.0 ELSE 0.0 END) AS major_comp_rate_general
  FROM (
    SELECT hadm_id,
           MAX(CASE
                 WHEN LOWER(dd.long_title) LIKE '%acute renal failure%' THEN 1
                 WHEN LOWER(dd.long_title) LIKE '%respiratory failure%' THEN 1
                 WHEN LOWER(dd.long_title) LIKE '%shock%' THEN 1
                 WHEN LOWER(dd.long_title) LIKE '%septic shock%' THEN 1
                 WHEN LOWER(dd.long_title) LIKE '%sepsis%' THEN 1
                 ELSE 0
               END) AS major_comp
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    GROUP BY hadm_id
  ) AS ddm
),
-- 9) Profile LOS percentile calculation
los_percentile AS (
  SELECT
    IFNULL(100.0 * SUM(CASE WHEN g.los < p.profile_avg_los_days THEN 1 ELSE 0 END) / NULLIF(SUM(1), 0), NULL) AS los_profile_percentile
  FROM profile_hadm AS ph
  CROSS JOIN profile_los AS p
  CROSS JOIN general_survivors AS g
)
-- 10) Final selection: compute requested metrics
SELECT
  ROUND(AVG(septic_metrics.charlson_score), 4) AS mean_risk_score,
  ROUND(SUM(septic_metrics.death_90) / NULLIF(COUNT(*), 0), 6) AS mortality_90d_profile,
  ROUND(AVG(septic_metrics.major_comp), 4) AS major_comp_rate_profile,
  (SELECT AVG(major_comp_rate_general) FROM major_comp_general) AS major_comp_rate_general,
  (SELECT los_profile_percentile FROM los_percentile) AS los_profile_percentile
FROM septic_metrics;