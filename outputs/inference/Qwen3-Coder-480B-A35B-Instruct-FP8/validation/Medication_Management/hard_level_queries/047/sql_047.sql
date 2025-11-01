WITH hemorrhagic_stroke_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%hemorrhage%' AND LOWER(long_title) LIKE '%brain%'
),

hemorrhagic_patients AS (
  SELECT DISTINCT di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN hemorrhagic_stroke_codes hsc
    ON di.icd_code = hsc.icd_code AND di.icd_version = hsc.icd_version
),

age_matched_patients AS (
  SELECT p.subject_id, p.gender, p.anchor_age,
         CASE WHEN hp.subject_id IS NOT NULL THEN 'Hemorrhagic_Stroke' ELSE 'Control' END AS cohort
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  LEFT JOIN hemorrhagic_patients hp ON p.subject_id = hp.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 48 AND 58
),

icu_admissions AS (
  SELECT ia.subject_id, ia.hadm_id, ia.stay_id, ia.intime, ia.outtime, ia.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ia
  JOIN age_matched_patients amp ON ia.subject_id = amp.subject_id
),

meds_first48hr AS (
  SELECT e.subject_id, e.hadm_id, ia.stay_id, e.medication,
         COUNT(DISTINCT e.medication) OVER (PARTITION BY e.subject_id) AS total_meds,
         SUM(CASE WHEN LOWER(e.medication) IN (
           'sertraline', 'fluoxetine', 'paroxetine', 'citalopram', 'escitalopram',
           'venlafaxine', 'desvenlafaxine', 'duloxetine', 'milnacipran',
           'sumatriptan', 'rizatriptan', 'naratriptan', 'zolmitriptan', 'eletriptan', 'frovatriptan'
         ) THEN 1 ELSE 0 END) OVER (PARTITION BY e.subject_id) AS serotonergic_meds
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN icu_admissions ia ON e.hadm_id = ia.hadm_id
  WHERE e.charttime BETWEEN ia.intime AND DATETIME_ADD(ia.intime, INTERVAL 48 HOUR)
),

med_complexity AS (
  SELECT subject_id,
         MAX(total_meds) AS total_meds,
         MAX(serotonergic_meds) AS serotonergic_meds,
         NTILE(4) OVER (ORDER BY MAX(total_meds)) AS med_complexity_quartile,
         CASE WHEN MAX(serotonergic_meds) >= 2 THEN '>=2 Serotonergic' ELSE '<2 Serotonergic' END AS serotonergic_category
  FROM meds_first48hr
  GROUP BY subject_id
),

final_cohort AS (
  SELECT amp.subject_id, amp.cohort,
         mc.total_meds, mc.serotonergic_meds, mc.med_complexity_quartile, mc.serotonergic_category,
         ia.los AS icu_los,
         adm.hospital_expire_flag AS mortality
  FROM age_matched_patients amp
  JOIN icu_admissions ia ON amp.subject_id = ia.subject_id
  JOIN med_complexity mc ON amp.subject_id = mc.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON ia.hadm_id = adm.hadm_id
)

SELECT cohort,
       serotonergic_category,
       med_complexity_quartile,
       COUNT(*) AS patient_count,
       AVG(icu_los) AS avg_icu_los,
       AVG(mortality) AS mortality_rate
FROM final_cohort
GROUP BY cohort, serotonergic_category, med_complexity_quartile
ORDER BY cohort, serotonergic_category, med_complexity_quartile;