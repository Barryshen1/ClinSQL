WITH SepsisAdmissions AS (
  SELECT DISTINCT
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    a.gender = 'M'
    AND d.icd_code = 'J84'
), PlateletCounts AS (
  SELECT
    l.hadm_id,
    l.valuenum AS platelet_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
    ON l.itemid = d.itemid
  WHERE
    l.hadm_id IN (SELECT hadm_id FROM SepsisAdmissions)
    AND d.label = 'Platelet count'
)
SELECT
  STDDEV(platelet_count)
FROM
  PlateletCounts;