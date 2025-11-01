WITH pe_patients AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, pat.gender, pat.anchor_age,
         adm.admittime, adm.dischtime, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.subject_id = dx.subject_id AND adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
    ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 74 AND 84
    AND (
      (dx.icd_version = 9 AND dx.icd_code LIKE '4151%')
      OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I26%')
    )
),
med_first24h AS (
  SELECT pr.subject_id, pr.hadm_id,
         COUNT(DISTINCT pr.pharmacy_id) AS med_count,
         COUNT(DISTINCT CASE
           WHEN LOWER(pr.drug) LIKE '%amiodarone%'
             OR LOWER(pr.drug) LIKE '%sotalol%'
             OR LOWER(pr.drug) LIKE '%haloperidol%'
             OR LOWER(pr.drug) LIKE '%ciprofloxacin%'
           THEN pr.pharmacy_id END) AS qt_count,
         COUNT(DISTINCT CASE
           WHEN LOWER(pr.drug) LIKE '%warfarin%'
             OR LOWER(pr.drug) LIKE '%heparin%'
             OR LOWER(pr.drug) LIKE '%enoxaparin%'
             OR LOWER(pr.drug) LIKE '%apixaban%'
             OR LOWER(pr.drug) LIKE '%dabigatran%'
           THEN pr.pharmacy_id END) AS bleed_count
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN pe_patients coh
    ON pr.subject_id = coh.subject_id AND pr.hadm_id = coh.hadm_id
  WHERE pr.starttime <= DATETIME_ADD(coh.admittime, INTERVAL 24 HOUR)
  GROUP BY pr.subject_id, pr.hadm_id
),
with_percentiles AS (
  SELECT m.*, 
         PERCENT_RANK() OVER (ORDER BY med_count) AS complexity_percentile
  FROM med_first24h m
),
icu_flags AS (
  SELECT DISTINCT subject_id, hadm_id, 1 AS icu_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
final_base AS (
  SELECT p.subject_id, p.hadm_id,
         m.med_count, m.qt_count, m.bleed_count,
         m.complexity_percentile,
         CASE WHEN m.qt_count > 0 THEN 1 ELSE 0 END AS has_qt_drug,
         CASE WHEN m.bleed_count > 0 THEN 1 ELSE 0 END AS has_bleed_drug,
         CASE WHEN i.icu_flag = 1 THEN 1 ELSE 0 END AS icu_flag,
         DATETIME_DIFF(p.dischtime, p.admittime, DAY) AS los_days,
         p.hospital_expire_flag
  FROM pe_patients p
  JOIN with_percentiles m
    ON p.subject_id = m.subject_id AND p.hadm_id = m.hadm_id
  LEFT JOIN icu_flags i
    ON p.subject_id = i.subject_id AND p.hadm_id = i.hadm_id
),
los_quartiles AS (
  SELECT los_days,
         PERCENTILE_CONT(los_days, 0.75) OVER() AS los_p75
  FROM final_base
  QUALIFY ROW_NUMBER() OVER (ORDER BY hadm_id) = 1 -- just to get los_p75 distinct
),
top_los AS (
  SELECT DISTINCT f.*, 
         CASE WHEN f.los_days >= q.los_p75 THEN 1 ELSE 0 END AS top_quartile_los
  FROM final_base f
  CROSS JOIN (SELECT DISTINCT los_p75 FROM los_quartiles) q
)
SELECT 
  icu_flag,
  COUNT(*) AS n_admissions,
  ROUND(AVG(med_count),2) AS mean_complexity,
  MIN(med_count) AS min_complexity,
  MAX(med_count) AS max_complexity,
  ROUND(STDDEV(med_count),2) AS sd_complexity,
  ROUND(AVG(has_qt_drug)*100,1) AS pct_with_qt_drug,
  ROUND(AVG(has_bleed_drug)*100,1) AS pct_with_bleed_drug,
  ROUND(AVG(complexity_percentile),3) AS mean_complexity_percentile,
  ROUND(AVG(top_quartile_los)*100,1) AS pct_top_quartile_los,
  ROUND(AVG(hospital_expire_flag)*100,1) AS mortality_rate_pct
FROM top_los
GROUP BY icu_flag
ORDER BY icu_flag;