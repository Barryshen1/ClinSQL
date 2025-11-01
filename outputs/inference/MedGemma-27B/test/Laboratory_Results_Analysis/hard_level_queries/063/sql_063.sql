WITH PatientCohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND d.icd_code = 'I26.9' -- Pulmonary embolism code
), LabInstability AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    AVG(li.lab_instability_score) AS avg_lab_instability_score
  FROM PatientCohort AS pc
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON pc.subject_id = le.subject_id AND pc.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  LEFT JOIN (
    SELECT
      subject_id,
      hadm_id,
      itemid,
      charttime,
      valuenum,
      valueuom,
      -- Calculate lab instability score for each lab event
      CASE
        WHEN dli.category = 'Laboratory' THEN
          CASE
            WHEN dli.label = 'Creatinine' THEN
              CASE
                WHEN valuenum > 1.5 THEN 1
                ELSE 0
              END
            WHEN dli.label = 'BUN' THEN
              CASE
                WHEN valuenum > 20 THEN 1
                ELSE 0
              END
            WHEN dli.label = 'WBC' THEN
              CASE
                WHEN valuenum > 12 THEN 1
                ELSE 0
              END
            WHEN dli.label = 'Platelet Count' THEN
              CASE
                WHEN valuenum < 150000 THEN 1
                ELSE 0
              END
            ELSE 0
          END
        ELSE 0
      END AS lab_instability_score
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
      ON le.itemid = dli.itemid
    WHERE
      dli.category = 'Laboratory'
      AND dli.label IN ('Creatinine', 'BUN', 'WBC', 'Platelet Count')
  ) AS li
    ON pc.subject_id = li.subject_id
    AND pc.hadm_id = li.hadm_id
    AND le.charttime = li.charttime
    AND le.itemid = li.itemid
  GROUP BY
    pc.subject_id,
    pc.hadm_id
), Threshold AS (
  SELECT
    PERCENTILE_CONT(avg_lab_instability_score, 0.75) AS p75_threshold
  FROM LabInstability
), FinalCohort AS (
  SELECT
    li.subject_id,
    li.hadm_id
  FROM LabInstability AS li
  JOIN Threshold AS t
    ON li.avg_lab_instability_score >= t.p75_threshold
), Mortality AS (
  SELECT
    fc.subject_id,
    fc.hadm_id,
    COUNT(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE NULL END) AS mortality_flag
  FROM FinalCohort AS fc
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON fc.subject_id = a.subject_id AND fc.hadm_id = a.hadm_id
  GROUP BY
    fc.subject_id,
    fc.hadm_id
), LOS AS (
  SELECT
    fc.subject_id,
    fc.hadm_id,
    (a.dischtime - a.admittime) AS los_interval
  FROM FinalCohort AS fc
  JOIN `physion;