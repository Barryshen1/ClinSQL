SELECT
      subject_id,
      hadm_id,
      troponin_value,
      troponin_uln,
      CASE
        WHEN troponin_uln IS NULL THEN 0
        ELSE troponin_uln * 0.99
      END AS troponin_99th_percentile_uln
    FROM
      LabResults;