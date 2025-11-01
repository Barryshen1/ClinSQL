WITH PatientACS AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
    AND a.admission_type = 'EMERGENCY'
),
Troponin AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    le.charttime,
    le.valuenum AS troponin_value,
    le.valueuom AS troponin_uom
  FROM PatientACS AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON p.subject_id = le.subject_id AND p.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE
    dli.label = 'Troponin T'
    AND le.charttime BETWEEN p.admittime AND p.admittime + INTERVAL '24' HOUR
),
TroponinCategory AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN troponin_value < 0.01 THEN 'Normal/Minimal'
      WHEN troponin_value BETWEEN 0.01 AND 0.09 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category
  FROM Troponin
  WHERE
    troponin_value IS NOT NULL
    AND troponin_uom = 'ng/mL'
)
SELECT
  tc.troponin_category,
  COUNT(DISTINCT tc.subject_id) AS patient_count,
  COUNT(DISTINCT tc.subject_id) * 100.0 / SUM(COUNT(DISTINCT tc.subject_id)) OVER () AS percentage,
  SUM(CASE WHEN pac.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT tc.subject_id) AS mortality_rate
FROM TroponinCategory AS tc
INNER JOIN PatientACS AS pac
  ON tc.subject_id = pac.subject_id AND tc.hadm_id = pac.hadm_id
GROUP BY
  tc.troponin_category
ORDER BY
  tc.troponin_category;