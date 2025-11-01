WITH PatientPneumonia AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND d.icd_code LIKE 'J18%' -- Pneumonia ICD-10 codes
),
MedicationComplexity AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    COUNT(DISTINCT e.medication) AS unique_drugs -- Changed 'drug' to 'medication'
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS h
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` AS e
    ON h.hadm_id = e.hadm_id
  WHERE
    e.charttime BETWEEN h.admittime AND TIMESTAMP_ADD(h.admittime, INTERVAL 7 DAY)
  GROUP BY
    h.subject_id,
    h.hadm_id
),
AdmissionData AS (
  SELECT
    h.hadm_id,
    h.subject_id,
    h.admittime,
    h.dischtime,
    h.deathtime,
    h.hospital_expire_flag,
    mc.unique_drugs,
    h.los AS hospital_los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS h
  JOIN
    MedicationComplexity AS mc
    ON h.hadm_id = mc.hadm_id
  WHERE
    h.subject_id IN (SELECT subject_id FROM PatientPneumonia)
),
Tertiles AS (
  SELECT
    hadm_id,
    unique_drugs,
    NTILE(3) OVER (ORDER BY unique_drugs ASC) AS tertile
  FROM
    AdmissionData
),
Mortality AS (
  SELECT
    t.hadm_id,
    t.tertile,
    CASE WHEN t.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS mortality
  FROM
    Tertiles AS t
),
Readmission AS (
  SELECT
    t.hadm_id,
    t.tertile,
    CASE WHEN EXISTS (
      SELECT
        1
      FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS h2
      WHERE
        h2.subject_id = t.subject_id
        AND h2.admittime > t.dischtime
        AND h2.admittime <= TIMESTAMP_ADD(t.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmission
  FROM
    Tertiles AS t
),
FinalData AS (
  SELECT
    t.tertile,
    COUNT(t.hadm_id) AS count,
    MIN(mc.unique_drugs) -- This is the line with the error
  FROM
    Tertiles AS t
  JOIN
    MedicationComplexity AS mc
    ON t.hadm_id = mc.hadm_id
  GROUP BY
    t.tertile
)
SELECT
  fd.tertile,
  COUNT(fd.hadm_id) AS count,
  MIN(fd.unique_drugs) AS min_score,
  AVG(fd.unique_drugs) AS avg_score,
  MAX(fd.unique_drugs) AS max_score,
  AVG(ad.hospital_los) AS mean_los,
  AVG(fd.mortality) AS mortality_percent,
  AVG(fd.readmission) AS readmission_percent
FROM
  FinalData AS fd
JOIN
  AdmissionData AS ad
  ON fd.hadm_id = ad.hadm_id
GROUP BY
  fd.tertile
ORDER BY
  fd.tertile;