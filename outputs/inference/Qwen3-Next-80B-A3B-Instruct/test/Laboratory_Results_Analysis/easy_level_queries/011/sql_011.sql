WITH peak_potassium_per_stay AS (
  SELECT 
    i.stay_id,
    MAX(le.valuenum) AS peak_potassium_meq_l
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
    INNER JOIN physionet-data.mimiciv_3_1_icu.icustays i 
      ON p.subject_id = i.subject_id
    INNER JOIN physionet-data.mimiciv_3_1_hosp.labevents le 
      ON i.subject_id = le.subject_id AND i.hadm_id = le.hadm_id
    INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems d 
      ON le.itemid = d.itemid
  WHERE 
    p.anchor_age = 56
    AND p.gender = 'M'
    AND d.label = 'Potassium'
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'mEq/L'  -- Ensure unit is mEq/L as specified
  GROUP BY 
    i.stay_id
)
SELECT 
  STDDEV_POP(peak_potassium_meq_l) AS std_dev_peak_potassium_meq_l
FROM 
  peak_potassium_per_stay;