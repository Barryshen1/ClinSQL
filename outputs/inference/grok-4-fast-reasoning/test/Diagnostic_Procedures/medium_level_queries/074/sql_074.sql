WITH first_stays AS (
  SELECT 
    subject_id, 
    hadm_id, 
    first_careunit, 
    los,
    ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY stay_id ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE los >= 1 AND los <= 7
),
patients_with_stroke AS (
  SELECT DISTINCT 
    a.subject_id, 
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age >= 40 
    AND p.anchor_age <= 50
    AND (
      (d.icd_version = 9 
       AND d.icd_code IN ('43301', '43311', '43321', '43331', '43381', '43391', 
                          '43401', '43411', '43491', '436'))
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
    )
),
eligible_admissions AS (
  SELECT 
    fs.subject_id,
    fs.hadm_id,
    fs.first_careunit,
    fs.los,
    CASE 
      WHEN fs.los <= 4 THEN '1-4' 
      ELSE '5-7' 
    END AS los_group
  FROM first_stays fs
  INNER JOIN patients_with_stroke pws 
    ON fs.subject_id = pws.subject_id AND fs.hadm_id = pws.hadm_id
  WHERE fs.rn = 1
),
imaging_counts AS (
  SELECT 
    pi.hadm_id,
    COUNT(*) AS num_imaging
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%tomography%'
     OR LOWER(dip.long_title) LIKE '%resonance%'
     OR LOWER(dip.long_title) LIKE '%radiography%'
     OR LOWER(dip.long_title) LIKE '%ultrasound%'
     OR LOWER(dip.long_title) LIKE '%sonography%'
     OR LOWER(dip.long_title) LIKE '%angiography%'
     OR LOWER(dip.long_title) LIKE '%nuclear%'
  GROUP BY pi.hadm_id
)
SELECT 
  ea.los_group,
  ea.first_careunit,
  AVG(COALESCE(ic.num_imaging, 0)) AS mean_imaging,
  MIN(COALESCE(ic.num_imaging, 0)) AS min_imaging,
  MAX(COALESCE(ic.num_imaging, 0)) AS max_imaging
FROM eligible_admissions ea
LEFT JOIN imaging_counts ic 
  ON ea.hadm_id = ic.hadm_id
GROUP BY ea.los_group, ea.first_careunit
ORDER BY ea.los_group, ea.first_careunit;