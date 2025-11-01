WITH dka_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  WHERE LOWER(d.long_title) LIKE '%diabetic ketoacidosis%'
    AND LOWER(p.gender) = 'f'
),
glucose_peaks AS (
  SELECT g.hadm_id, MAX(l.valuenum) AS peak_glucose
  FROM dka_admissions g
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON l.hadm_id = g.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON li.itemid = l.itemid
  WHERE LOWER(li.label) LIKE '%glucose%'
    AND LOWER(li.fluid) LIKE '%serum%'
  GROUP BY g.hadm_id
),
numbered AS (
  SELECT peak_glucose,
         ROW_NUMBER() OVER (ORDER BY peak_glucose) AS rn,
         COUNT(*) OVER () AS total
  FROM glucose_peaks
),
median_calc AS (
  SELECT
     CASE
       WHEN MOD(total, 2) = 1 THEN
         (SELECT peak_glucose FROM numbered n2 WHERE n2.rn = (total + 1) / 2)
       ELSE
         (SELECT AVG(peak_glucose) FROM numbered n2 WHERE n2.rn IN (total/2, total/2 + 1))
     END AS median_peak_glucose
  FROM numbered
  LIMIT 1
)
SELECT median_peak_glucose AS median_peak_serum_glucose
FROM median_calc;