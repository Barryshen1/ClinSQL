WITH item_ids AS (
  SELECT
    MAX(IF(label = 'Vital Instability Index', itemid, NULL)) AS vii_itemid,
    MAX(IF(label LIKE 'Mean Arterial Pressure%', itemid, NULL)) AS map_itemid,
    MAX(IF(label LIKE 'Heart Rate%', itemid, NULL)) AS hr_itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
),
respiratory_failure_hadm AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON diag.icd_code = dd.icd_code AND diag.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%respiratory failure%'
),
icu_first_stays AS (
  SELECT subject_id, hadm_id, stay_id, intime, outtime, los,
         ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
cohorts AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime, icu.los,
         pat.gender, pat.anchor_age, adm.hospital_expire_flag,
         CASE WHEN pat.gender = 'M' AND pat.anchor_age BETWEEN 40 AND 50 THEN 'male_40_50' ELSE 'all_resp_fail' END AS cohort_type
  FROM icu_first_stays icu
  JOIN respiratory_failure_hadm rf ON icu.subject_id = rf.subject_id AND icu.hadm_id = rf.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON icu.subject_id = adm.subject_id AND icu.hadm_id = adm.hadm_id
  WHERE icu.rn = 1
),
vitals_48h AS (
  SELECT c.cohort_type, c.stay_id, c.subject_id, ce.itemid, ce.valuenum,
         ce.charttime, c.intime
  FROM cohorts c
  CROSS JOIN item_ids ids
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id AND c.stay_id = ce.stay_id
  WHERE ce.itemid IN (ids.vii_itemid, ids.map_itemid, ids.hr_itemid)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
),
burden_per_stay AS (
  SELECT
    cohort_type, stay_id,
    AVG(CASE WHEN itemid = vii_itemid THEN valuenum END) AS mean_vii,
    STDDEV(CASE WHEN itemid = vii_itemid THEN valuenum END) AS sd_vii,
    SUM(CASE WHEN itemid = map_itemid AND valuenum < 65 THEN 1 ELSE 0 END) 
      / NULLIF(SUM(CASE WHEN itemid = map_itemid THEN 1 ELSE 0 END), 0) AS hypotensive_burden,
    SUM(CASE WHEN itemid = hr_itemid AND valuenum > 100 THEN 1 ELSE 0 END) 
      / NULLIF(SUM(CASE WHEN itemid = hr_itemid THEN 1 ELSE 0 END), 0) AS tachycardic_burden
  FROM vitals_48h
  CROSS JOIN item_ids
  GROUP BY cohort_type, stay_id
),
cohort_summary AS (
  SELECT
    c.cohort_type,
    AVG(b.hypotensive_burden) AS avg_hypotensive_burden,
    AVG(b.tachycardic_burden) AS avg_tachycardic_burden,
    AVG(c.los) AS avg_icu_los,
    AVG(c.hospital_expire_flag) AS mortality_rate
  FROM burden_per_stay b
  JOIN cohorts c ON b.stay_id = c.stay_id
  GROUP BY c.cohort_type
),
vii_stats AS (
  SELECT
    cohort_type,
    STDDEV(v.valuenum) AS sd_vii_all,
    APPROX_QUANTILES(v.valuenum, 100)[OFFSET(25)] AS p25_vii,
    APPROX_QUANTILES(v.valuenum, 100)[OFFSET(50)] AS p50_vii,
    APPROX_QUANTILES(v.valuenum, 100)[OFFSET(75)] AS p75_vii,
    APPROX_QUANTILES(v.valuenum, 100)[OFFSET(95)] AS p95_vii
  FROM vitals_48h v
  CROSS JOIN item_ids ids
  WHERE v.itemid = ids.vii_itemid
  GROUP BY cohort_type
)
SELECT s.cohort_type,
       s.avg_hypotensive_burden,
       s.avg_tachycardic_burden,
       s.avg_icu_los,
       s.mortality_rate,
       v.sd_vii_all,
       v.p25_vii, v.p50_vii, v.p75_vii, v.p95_vii
FROM cohort_summary s
JOIN vii_stats v USING(cohort_type)
ORDER BY cohort_type;