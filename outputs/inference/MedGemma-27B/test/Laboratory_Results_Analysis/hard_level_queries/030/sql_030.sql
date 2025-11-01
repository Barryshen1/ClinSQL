WITH Cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.admission_type = 'EMERGENCY'
    AND di.long_title LIKE '%asthma%'
    AND a.gender = 'F'
    AND a.anchor_age BETWEEN 39 AND 49
  GROUP BY
    a.subject_id,
    a.hadm_id
),
LabInstability AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.charttime,
    c.valuenum,
    c.valueuom,
    d.label AS lab_name
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS d
    ON c.itemid = d.itemid
  WHERE
    c.subject_id IN (
      SELECT
        subject_id
      FROM Cohort
    )
    AND c.hadm_id IN (
      SELECT
        hadm_id
      FROM Cohort
    )
    AND c.charttime BETWEEN (
      SELECT
        MIN(a.admittime)
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      INNER JOIN Cohort AS co
        ON a.hadm_id = co.hadm_id
    ) AND (
      SELECT
        MIN(a.admittime)
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      INNER JOIN Cohort AS co
        ON a.hadm_id = co.hadm_id
    ) + INTERVAL '48' HOUR
),
LabInstabilityScore AS (
  SELECT
    subject_id,
    hadm_id,
    PERCENTILE_CONT(valuenum, 0.75) OVER (PARTITION BY subject_id, hadm_id) AS lab_instability_score
  FROM LabInstability
)
SELECT
  AVG(lab_instability_score) AS avg_75th_percentile_lab_instability_score,
  AVG(i.los) AS avg_los,
  AVG(i.hospital_expire_flag) AS avg_in_hospital_mortality
FROM LabInstabilityScore AS lis
INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
  ON lis.subject_id = i.subject_id AND lis.hadm_id = i.hadm_id;