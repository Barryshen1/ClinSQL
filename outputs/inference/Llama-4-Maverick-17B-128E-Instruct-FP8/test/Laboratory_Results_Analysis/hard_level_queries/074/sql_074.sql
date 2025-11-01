WITH heart_failure_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diags ON p.subject_id = diags.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON diags.icd_code = di.icd_code AND diags.icd_version = di.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 37 AND 47
  AND di.long_title LIKE '%Heart failure%'
),
lab_instability AS (
  SELECT hf.subject_id, COUNT(DISTINCT l.itemid) as lab_score
  FROM heart_failure_patients hf
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON hf.subject_id = icu.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON icu.hadm_id = l.hadm_id
  WHERE TIMESTAMP_DIFF(l.charttime, icu.intime, HOUR) <= 72
  AND ((l.valuenum < (SELECT MIN(ref_range_lower) FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` dl WHERE dl.itemid = l.itemid)) OR 
       (l.valuenum > (SELECT MAX(ref_range_upper) FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` dl WHERE dl.itemid = l.itemid)))
  GROUP BY hf.subject_id
),
patient_outcomes AS (
  SELECT icu.subject_id, 
         MAX(TIMESTAMP_DIFF(icu.outtime, icu.intime, HOUR)) as los_hours,
         MAX(CASE WHEN a.deathtime IS NOT NULL THEN 1 ELSE 0 END) as mortality_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON icu.hadm_id = a.hadm_id
  GROUP BY icu.subject_id
)
SELECT li.lab_score, po.los_hours, po.mortality_flag
FROM lab_instability li
JOIN patient_outcomes po ON li.subject_id = po.subject_id;