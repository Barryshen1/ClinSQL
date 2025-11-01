SELECT
  APPROX_QUANTILES(l.valuenum, 1000)[OFFSET(750)] AS p75_potassium
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
WHERE
  p.gender = 'M'
  AND a.dischtime IS NOT NULL
  AND l.itemid = 50822  -- Serum potassium (verified in d_labitems)
  AND DATE(l.charttime) = DATE(a.dischtime)
  AND l.valuenum IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    WHERE i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  );