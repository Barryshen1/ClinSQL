WITH AMIAdmits AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code
   AND d.icd_version = di.icd_version
  WHERE di.long_title LIKE '%myocardial infarction%'
),
Population AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los,
    CASE WHEN adm.deathtime IS NOT NULL THEN 1 ELSE 0 END AS death
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON adm.hadm_id = icu.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON pat.subject_id = icu.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 76 AND 86
    AND icu.hadm_id IN (SELECT hadm_id FROM AMIAdmits)
),
ProcCounts AS (
  SELECT
    icu.hadm_id,
    icu.stay_id,
    COUNT(DISTINCT pe.itemid) AS proc_cnt
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON pe.hadm_id = icu.hadm_id
   AND pe.stay_id = icu.stay_id
  WHERE pe.starttime >= icu.intime
    AND pe.starttime < TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY icu.hadm_id, icu.stay_id
)
SELECT
  quartile,
  AVG(proc_cnt) AS mean_proc_count,
  AVG(los)  AS mean_icu_los,
  AVG(death) * 100 AS hospital_mortality_percent
FROM (
  SELECT
     p.subject_id,
     p.hadm_id,
     p.stay_id,
     p.intime,
     p.los,
     COALESCE(pc.proc_cnt, 0) AS proc_cnt,
     p.death,
     NTILE(4) OVER (ORDER BY COALESCE(pc.proc_cnt, 0)) AS quartile
  FROM Population AS p
  LEFT JOIN ProcCounts AS pc
    ON pc.hadm_id = p.hadm_id
   AND pc.stay_id = p.stay_id
) AS t
GROUP BY quartile
ORDER BY quartile;