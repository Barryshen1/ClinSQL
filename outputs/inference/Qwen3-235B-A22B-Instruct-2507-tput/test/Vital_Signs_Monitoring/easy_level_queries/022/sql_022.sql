SELECT AVG(max_map) AS avg_of_max_map
FROM (
  SELECT ce.stay_id, MAX(ce.valuenum) AS max_map
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays ce_stay
    ON p.subject_id = ce_stay.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
    ON ce_stay.stay_id = ce.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND LOWER(di.label) LIKE '%mean%' 
    AND LOWER(di.label) LIKE '%arterial%'
    AND LOWER(di.label) LIKE '%pressure%'
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
) AS stay_max_map;