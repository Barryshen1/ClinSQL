WITH Cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.gender = 'M'
    AND a.anchor_age BETWEEN 70 AND 80
    AND di.long_title LIKE '%hemorrhagic stroke%'
    AND d.seq_num = 1
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
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS d
    ON c.itemid = d.itemid
  WHERE
    c.hadm_id IN (
      SELECT
        hadm_id
      FROM Cohort
    )
    AND c.charttime BETWEEN (
      SELECT
        MIN(a.intime)
      FROM `physionet-data.mimiciv_3_1_icu.icustays` AS a
      JOIN Cohort AS co
        ON a.hadm_id = co.hadm_id
    ) AND (
      SELECT
        MIN(a.intime)
      FROM `physionet-data.mimiciv_3_1_icu.icustays` AS a
      JOIN Cohort AS co
        ON a.hadm_id = co.hadm_id
    ) + INTERVAL '48' HOUR
),
CohortStats AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    AVG(l.valuenum) AS avg_lab_value,
    STDDEV(l.valuenum) AS stddev_lab_value
  FROM Cohort AS c
  JOIN LabInstability AS l
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
  GROUP BY
    c.subject_id,
    c.hadm_id
),
CohortLabInstabilityScore AS (
  SELECT
    cs.subject_id,
    cs.hadm_id,
    (l.valuenum - cs.avg_lab_value) / cs.stddev_lab_value AS lab_instability_score
  FROM CohortStats AS cs
  JOIN LabInstability AS l
    ON cs.subject_id = l.subject_id AND cs.hadm_id = l.hadm_id
),
CohortPercentile AS (
  SELECT
    PERCENTILE_CONT(lab_instability_score, 0.25) AS percentile_25
  FROM CohortLabInstabilityScore
),
GeneralStats AS (
  SELECT
    COUNT(DISTINCT c.subject_id) AS total_inpatient_count,
    COUNT(DISTINCT c.hadm_id) AS total_inpatient_admissions,
    AVG(c.los) AS avg_los,
    AVG(a.hospital_expire_flag) AS avg_mortality
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.icustays` AS c
    ON a.hadm_id = c.hadm_id
),
CohortStatsFinal AS (
  SELECT
    COUNT(DISTINCT c.subject_id) AS cohort_count,
    COUNT(DISTINCT c.hadm_id) AS cohort_admissions,
    AVG(c.los) AS cohort_los,
    AVG(a.hospital_expire_flag) AS cohort_mortality
  FROM `;