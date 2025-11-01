WITH tia_patients AS (
  SELECT DISTINCT adm.subject_id,
         adm.hadm_id,
         DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
         pat.gender,
         pat.anchor_age,
         CASE 
           WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
           ELSE '4-7'
         END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 64 AND 74
    AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '435%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'G45%')
    )
),
proc_counts AS (
  SELECT tp.subject_id,
         tp.hadm_id,
         tp.los_days,
         tp.los_group,
         COUNT(DISTINCT proc.icd_code) AS proc_count
  FROM tia_patients tp
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON tp.hadm_id = proc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
    ON proc.icd_code = dproc.icd_code
    AND proc.icd_version = dproc.icd_version
  WHERE LOWER(dproc.long_title) LIKE '%ultrasound%'
     OR LOWER(dproc.long_title) LIKE '%echocardiogram%'
  GROUP BY tp.subject_id, tp.hadm_id, tp.los_days, tp.los_group
),
icu_flag AS (
  SELECT hadm_id, 1 AS icu_use
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
final AS (
  SELECT pc.los_group,
         IFNULL(icu.icu_use,0) AS icu_use,
         pc.proc_count
  FROM proc_counts pc
  LEFT JOIN icu_flag icu
    ON pc.hadm_id = icu.hadm_id
)
SELECT los_group,
       icu_use,
       AVG(proc_count) AS mean_ultrasound_echo_per_adm
FROM final
GROUP BY los_group, icu_use
ORDER BY los_group, icu_use;