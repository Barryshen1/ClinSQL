WITH patient_core AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 51 AND 61
),
postop_dx AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%postoperative complication%'
     OR (LOWER(dd.long_title) LIKE '%complication%' AND LOWER(dd.long_title) LIKE '%procedure%')
),
admit_base AS (
  SELECT a.subject_id, a.hadm_id,
         a.admittime, a.dischtime,
         ROUND(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24,1) AS los_days,
         a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patient_core p USING(subject_id)
  JOIN postop_dx po USING(hadm_id)
),
icu_flag AS (
  SELECT hadm_id, 1 AS icu_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
comorbs AS (
  SELECT hadm_id,
         -- Charlson component weights (simplified)
         SUM(
           CASE 
             WHEN (icd_version = 9 AND icd_code BETWEEN '5850' AND '5859')
               OR (icd_version = 10 AND (icd_code LIKE 'N18%' OR icd_code LIKE 'Z49%' OR icd_code LIKE 'Z94.0%' OR icd_code LIKE 'Z99.2%'))
             THEN 2 ELSE 0 END
         ) AS ckd_score,
         SUM(
           CASE 
             WHEN (icd_version = 9 AND (icd_code LIKE '250%' OR icd_code BETWEEN '2490' AND '2499'))
               OR (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%'))
             THEN 1 ELSE 0 END
         ) AS dm_score,
         SUM(
           CASE
             -- Example limited Charlson mapping
             WHEN (icd_version = 9 AND icd_code LIKE '428%') OR (icd_version = 10 AND icd_code LIKE 'I50%') THEN 1 -- CHF
             WHEN (icd_version = 9 AND (icd_code BETWEEN '5850' AND '5859'))
               OR (icd_version = 10 AND (icd_code LIKE 'N18%' OR icd_code LIKE 'Z49%' OR icd_code LIKE 'Z94.0%' OR icd_code LIKE 'Z99.2%'))
               THEN 2 -- CKD
             WHEN (icd_version = 9 AND icd_code LIKE '250%') 
               OR (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%'))
               THEN 1 -- DM
             ELSE 0
           END
         ) AS cci_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
adm_with_flags AS (
  SELECT ab.subject_id, ab.hadm_id,
         ab.los_days,
         CASE WHEN io.icu_flag=1 THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
         CASE 
           WHEN ab.los_days BETWEEN 1 AND 2 THEN '1-2'
           WHEN ab.los_days BETWEEN 3 AND 5 THEN '3-5'
           WHEN ab.los_days BETWEEN 6 AND 9 THEN '6-9'
           WHEN ab.los_days >= 10 THEN '>=10'
           ELSE 'Unknown'
         END AS los_group,
         CASE 
           WHEN cci_score <= 1 THEN '0-1'
           WHEN cci_score = 2 THEN '2'
           WHEN cci_score >= 3 THEN '>=3'
           ELSE 'Unknown'
         END AS cci_group,
         ab.hospital_expire_flag,
         CASE WHEN ckd_score>0 THEN 1 ELSE 0 END AS has_ckd,
         CASE WHEN dm_score>0 THEN 1 ELSE 0 END AS has_dm
  FROM admit_base ab
  LEFT JOIN icu_flag io USING(hadm_id)
  LEFT JOIN comorbs c USING(hadm_id)
)
SELECT 
  icu_status,
  los_group,
  cci_group,
  COUNT(*) AS n_admissions,
  ROUND(100*SUM(hospital_expire_flag)/COUNT(*),1) AS mortality_pct,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los,
  ROUND(100*SUM(has_ckd)/COUNT(*),1) AS ckd_pct,
  ROUND(100*SUM(has_dm)/COUNT(*),1) AS dm_pct
FROM adm_with_flags
GROUP BY icu_status, los_group, cci_group
ORDER BY icu_status, los_group, cci_group;