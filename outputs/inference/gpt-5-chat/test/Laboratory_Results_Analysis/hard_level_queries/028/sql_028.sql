WITH
-- 1. Identify ICH diagnosis codes (ICD9 + ICD10)
ich_dx AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND (icd_code LIKE '431%' OR icd_code LIKE '432%'))
     OR (icd_version = 10 AND (icd_code LIKE 'I61%' OR icd_code LIKE 'I62%'))
),
-- 2. Admissions with ICH for target age/gender
cohort_ich AS (
  SELECT adm.subject_id, adm.hadm_id, pat.anchor_age, pat.gender,
         adm.admittime, adm.dischtime, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.subject_id = dx.subject_id
   AND adm.hadm_id = dx.hadm_id
  JOIN ich_dx dcode
    ON dx.icd_code = dcode.icd_code
   AND dx.icd_version = dcode.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 74 AND 84
),
-- 3. Controls: same age/gender, but no ICH dx
cohort_ctrl AS (
  SELECT adm.subject_id, adm.hadm_id, pat.anchor_age, pat.gender,
         adm.admittime, adm.dischtime, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 74 AND 84
    AND adm.hadm_id NOT IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      JOIN ich_dx dcode
        ON dx.icd_code = dcode.icd_code
       AND dx.icd_version = dcode.icd_version
    )
),
-- 4. Lab instability in first 72h — distinct abnormal labs
lab_instability AS (
  SELECT coh.ctype, coh.subject_id, coh.hadm_id, COUNT(DISTINCT le.itemid) AS abnormal_lab_types
  FROM (
    SELECT 'ICH' AS ctype, subject_id, hadm_id, anchor_age, gender, admittime, dischtime, hospital_expire_flag
    FROM cohort_ich
    UNION ALL
    SELECT 'CTRL' AS ctype, subject_id, hadm_id, anchor_age, gender, admittime, dischtime, hospital_expire_flag
    FROM cohort_ctrl
  ) coh
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON coh.subject_id = le.subject_id
   AND coh.hadm_id = le.hadm_id
  WHERE le.charttime BETWEEN coh.admittime AND TIMESTAMP_ADD(coh.admittime, INTERVAL 72 HOUR)
    AND le.flag IS NOT NULL
    AND LOWER(le.flag) LIKE '%abnormal%'
  GROUP BY coh.ctype, coh.subject_id, coh.hadm_id
),
-- 5. Quintiles for ICH group
ich_quintiles AS (
  SELECT li.*, 
         NTILE(5) OVER (ORDER BY abnormal_lab_types) AS quintile
  FROM lab_instability li
  WHERE li.ctype = 'ICH'
),
-- 6. Establish quintile cutoffs from ICH
ich_quintile_bounds AS (
  SELECT quintile,
         MIN(abnormal_lab_types) AS min_abn,
         MAX(abnormal_lab_types) AS max_abn
  FROM ich_quintiles
  GROUP BY quintile
),
-- 7. Assign controls into quintiles based on ICH cutoffs
ctrl_with_quintiles AS (
  SELECT li.*,
         b.quintile
  FROM lab_instability li
  JOIN ich_quintile_bounds b
    ON li.abnormal_lab_types BETWEEN b.min_abn AND b.max_abn
  WHERE li.ctype = 'CTRL'
),
-- 8. Prepare LOS and mortality for all with quintiles
ich_w_outcomes AS (
  SELECT iq.quintile,
         ci.hospital_expire_flag,
         TIMESTAMP_DIFF(ci.dischtime, ci.admittime, DAY) AS los
  FROM ich_quintiles iq
  JOIN cohort_ich ci
    ON iq.subject_id = ci.subject_id
   AND iq.hadm_id = ci.hadm_id
),
ctrl_w_outcomes AS (
  SELECT cq.quintile,
         cc.hospital_expire_flag,
         TIMESTAMP_DIFF(cc.dischtime, cc.admittime, DAY) AS los
  FROM ctrl_with_quintiles cq
  JOIN cohort_ctrl cc
    ON cq.subject_id = cc.subject_id
   AND cq.hadm_id = cc.hadm_id
),
-- 9. Aggregate results
summary_ich AS (
  SELECT quintile,
         COUNT(*) AS n,
         AVG(CAST(hospital_expire_flag AS FLOAT64))*100 AS mortality_rate_pct,
         AVG(los) AS mean_los
  FROM ich_w_outcomes
  GROUP BY quintile
),
summary_ctrl AS (
  SELECT quintile,
         COUNT(*) AS n,
         AVG(CAST(hospital_expire_flag AS FLOAT64))*100 AS mortality_rate_pct,
         AVG(los) AS mean_los
  FROM ctrl_w_outcomes
  GROUP BY quintile
)
-- Final output: summaries side by side
SELECT 'ICH' AS cohort, * FROM summary_ich
UNION ALL
SELECT 'CTRL' AS cohort, * FROM summary_ctrl
ORDER BY cohort, quintile;