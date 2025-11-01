WITH sepsis_patients AS (
  SELECT DISTINCT p.subject_id, p.gender, 
         TRUNC((p.anchor_year - p.dob_year) / 10) * 10 AS age_decade,
         i.stay_id, i.hadm_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id
  WHERE p.gender = 'M' AND TRUNC((p.anchor_year - p.dob_year) / 10) * 10 = 80
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
      WHERE d.hadm_id = i.hadm_id AND dicd.long_title LIKE '%Sepsis%'
    )
),
med_complexity AS (
  SELECT i.stay_id, COUNT(DISTINCT i.itemid) AS med_count,
         SUM(CASE WHEN d.label LIKE '%QT-prolonging%' THEN 1 ELSE 0 END) AS qt_prolonging_count,
         SUM(CASE WHEN d.label LIKE '%Bleeding Risk%' THEN 1 ELSE 0 END) AS bleeding_risk_count
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON i.itemid = d.itemid
  WHERE i.stay_id IN (SELECT stay_id FROM sepsis_patients)
    AND TIMESTAMP_DIFF(i.starttime, sp.intime, HOUR) <= 24
  GROUP BY i.stay_id
),
risk_category AS (
  SELECT stay_id,
         CASE
           WHEN qt_prolonging_count > 0 AND bleeding_risk_count > 0 THEN 'Both'
           ELSE 'Other'
         END AS risk_category,
         med_count
  FROM med_complexity
)
SELECT risk_category, 
       PERCENTILE_CONT(med_count, 0.25) OVER (PARTITION BY risk_category) AS q1,
       PERCENTILE_CONT(med_count, 0.5) OVER (PARTITION BY risk_category) AS median,
       PERCENTILE_CONT(med_count, 0.75) OVER (PARTITION BY risk_category) AS q3,
       AVG(icu.los) AS avg_los,
       SUM(CASE WHEN h.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
FROM risk_category rc
JOIN sepsis_patients sp ON rc.stay_id = sp.stay_id
JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON rc.stay_id = icu.stay_id
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` h ON sp.hadm_id = h.hadm_id
WHERE rc.med_count >= (SELECT PERCENTILE_CONT(med_count, 0.75) OVER () FROM risk_category)
GROUP BY risk_category;