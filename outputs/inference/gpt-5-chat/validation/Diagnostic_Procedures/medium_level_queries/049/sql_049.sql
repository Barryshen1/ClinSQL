WITH sepsis_cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id,
         adm.admittime, adm.dischtime,
         p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON adm.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
    AND LOWER(dd.long_title) LIKE '%sepsis%'
    AND LOWER(dd.long_title) NOT LIKE '%septic shock%'
),
los_categorized AS (
  SELECT sc.subject_id, sc.hadm_id,
         DATE_DIFF(DATE(sc.dischtime), DATE(sc.admittime), DAY) AS los_days
  FROM sepsis_cohort sc
),
proc_counts AS (
  SELECT lc.hadm_id,
         COUNT(*) AS proc_count
  FROM los_categorized lc
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON lc.hadm_id = pr.hadm_id
  GROUP BY lc.hadm_id
),
los_with_proc AS (
  SELECT lc.hadm_id,
         CASE 
           WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
           WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
           ELSE NULL
         END AS los_group,
         pc.proc_count
  FROM los_categorized lc
  JOIN proc_counts pc
    ON lc.hadm_id = pc.hadm_id
)
SELECT los_group,
       AVG(proc_count) AS mean_diagnostic_procedures
FROM los_with_proc
WHERE los_group IS NOT NULL
GROUP BY los_group
ORDER BY los_group;